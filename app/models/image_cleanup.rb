# Deletes stored images nothing needs any more: images of expired spam
# (Event::SpamImages) and images no event uses (OrphanedImages). Dokku runs it
# daily (`bin/rails images:purge`, see app.json) against production S3,
# unattended and irreversibly, so a run deletes at most MAXIMUM_BLOBS_PER_RUN
# images, logs every blob it deletes, and can be previewed with DRY_RUN=1.
#
# Each image is deleted in one transaction: the caller's own rows (its
# attachment or ImageUpload), then, if nothing else uses the blob, the blob
# with its variants. Stored files are deleted after the commit, so a run
# interrupted before it leaves everything for the next run. A file whose
# delete fails (after the SDK's own retries), or a process killed right after
# the commit, leaves a stored file with no row, which no later run can find:
# the "could not delete stored file ... key=" log line is then the only record
# for removing it by hand.
#
# A dry run takes exactly the same steps, rolls each transaction back, and
# deletes no files; it cannot see blobs that its spam step would have detached.
class ImageCleanup
  # The 2026-11-20 production copy had 1,062 orphaned images (228 MB), and
  # fewer than 150 images that events still use; spam and abandoned uploads
  # add a few a day, up to 20 in a spam wave. 50 a day keeps up and clears the
  # backlog in about three weeks, while a wrong query could delete at most 50
  # images before someone reads the logs.
  MAXIMUM_BLOBS_PER_RUN = 50
  REASONS = %w[operator_spam automatic_spam unattached_upload unreferenced_legacy_upload].freeze

  Result = Data.define(:dry_run, :deleted_blobs, :deleted_bytes, :kept_shared_blobs, :failed_deletes, :limit_reached) do
    def to_s
      counts = REASONS.map { |reason| "#{reason}=#{deleted_blobs.fetch(reason, 0)}" }
      [ "images:purge", ("dry_run" if dry_run), *counts, "deleted_bytes=#{deleted_bytes}",
        "kept_shared_blobs=#{kept_shared_blobs}", "failed_deletes=#{failed_deletes}", "limit_reached=#{limit_reached}" ].compact.join(" ")
    end

    def success? = failed_deletes.zero?
  end

  attr_reader :now

  def self.run(...) = new(...).run

  def initialize(now: Time.current, dry_run: false, limit: MAXIMUM_BLOBS_PER_RUN, logger: Rails.logger)
    @now, @dry_run, @limit, @logger = now, dry_run, limit, logger
    @deleted_blobs = Hash.new(0)
    @deleted_bytes = @kept_shared_blobs = @failed_deletes = @removed_blobs = 0
  end

  def run
    Event::SpamImages.new(self).purge_expired
    OrphanedImages.new(self).purge
    result
  end

  def result
    Result.new(dry_run: dry_run?, deleted_blobs: @deleted_blobs.dup, deleted_bytes: @deleted_bytes,
      kept_shared_blobs: @kept_shared_blobs, failed_deletes: @failed_deletes, limit_reached: limit_reached?)
  end

  def dry_run? = @dry_run

  # Counts blobs whose rows went, whether or not their file delete worked:
  # a failing storage must not let a run remove rows without limit.
  def limit_reached? = @removed_blobs >= @limit

  # Reads every description once, before any transaction takes a row lock:
  # about 85 MB of HTML, 12 seconds, on the 2026-11 production copy.
  def read_descriptions
    references
    expired_spam_references
  end

  # Descriptions that still need their images: every event's, except spam
  # whose images have expired.
  def references
    @references ||= ImageReferences.in_descriptions_of(Event.where.not(id: expired_spam_ids))
  end

  # The descriptions left out of #references, by event, to check under lock
  # that they are still expired (see #referenced_by_revived_spam?).
  def expired_spam_references
    @expired_spam_references ||= ImageReferences.by_event(Event.where(id: expired_spam_ids))
  end

  # The block runs first in the transaction: it removes the caller's rows and
  # returns the reason for deleting the blob, or nil to leave everything as
  # it was. The blob itself goes only if nothing else is attached to it and no
  # description references it.
  def delete(blob)
    reason = deleted = nil
    # requires_new: a dry run inside an outer transaction still rolls back.
    ActiveRecord::Base.transaction(requires_new: true) do
      next unless (reason = yield)

      if blob.nil?
        # An attachment whose blob row is already gone.
      elsif in_use?(blob)
        @kept_shared_blobs += 1
      else
        deleted = destroy_rows(blob)
      end
      raise ActiveRecord::Rollback if dry_run?
    end
    delete_files(deleted, reason:) if deleted
  rescue ActiveRecord::InvalidForeignKey
    # Attached by a concurrent save after all (see #attached?); rolled back.
    @kept_shared_blobs += 1
  end

  private

  def expired_spam_ids
    @expired_spam_ids ||= Event.spam_images_expired(now).ids
  end

  def in_use?(blob)
    references.include?(blob) || referenced_by_revived_spam?(blob) || attached?(blob)
  end

  # Spam left out of #references because its images had expired, but marked
  # "Not spam" or edited since the run started: its description counts again.
  # Checked under the events' row locks, taken before the blob's.
  def referenced_by_revived_spam?(blob)
    event_ids = expired_spam_references.filter_map { |event_id, references| event_id if references.include?(blob) }
    event_ids.any? && Event.spam_images_expired(now).where(id: event_ids).lock.ids.size < event_ids.size
  end

  # Under the blob's row lock. Saving an attachment locks the blob row too,
  # through the foreign key, so a concurrent event save either committed first
  # and shows up here, or waits and then fails rather than point at a deleted
  # file. A blob row already gone counts as in use: there is nothing to delete.
  def attached?(blob)
    ActiveStorage::Blob.lock.where(id: blob.id).ids.empty? || blob.attachments.exists?
  end

  # Variants (resized copies) are blobs attached to variant records; Active
  # Storage would purge them in a background job, which a cron container
  # exits before running, so they go with their original.
  def destroy_rows(blob)
    variant_records = ActiveStorage::VariantRecord.where(blob_id: blob.id)
    variant_attachments = ActiveStorage::Attachment.where(record_type: "ActiveStorage::VariantRecord", record_id: variant_records.select(:id))
    variants = ActiveStorage::Blob.where(id: variant_attachments.select(:blob_id)).to_a
    variant_attachments.delete_all
    variant_records.delete_all
    [ blob, *variants ].each(&:destroy!)
  end

  def delete_files(blobs, reason:)
    @removed_blobs += 1
    blobs.each_with_index do |blob, index|
      blob.delete unless dry_run?
      @deleted_blobs[reason] += 1 if index.zero?
      @deleted_bytes += blob.byte_size
      @logger.info("images:purge #{dry_run? ? 'would delete' : 'deleted'} blob_id=#{blob.id} key=#{blob.key} " \
        "byte_size=#{blob.byte_size} reason=#{index.zero? ? reason : 'variant'}")
    rescue StandardError => e
      @failed_deletes += 1
      @logger.error("images:purge could not delete stored file blob_id=#{blob.id} key=#{blob.key}: #{e.class}: #{e.message}")
    end
  end
end
