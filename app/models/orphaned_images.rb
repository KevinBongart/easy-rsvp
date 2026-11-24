# Stored images no event uses: direct uploads never saved into an event or
# removed from one, images of deleted events, and legacy ImageUpload files no
# description links to any more. Anyone can upload images without creating an
# event, and their signed URLs never expire, so these would otherwise be free
# hosting forever. Deleted daily by ImageCleanup.
#
# A blob is orphaned when it is attached to nothing but ImageUpload records
# (which own legacy uploads but say nothing about their use) and no
# description references it (ImageReferences), counting spam descriptions
# until their images expire.
class OrphanedImages
  # Direct uploads reach storage before the event is saved. On the 2026-11
  # production copy every embed was attached within 14 minutes of its upload;
  # two days also covers a form left open overnight.
  GRACE_PERIOD = 2.days

  def initialize(cleanup)
    @cleanup = cleanup
  end

  def purge(batch_size: 100)
    cleanup.read_descriptions
    candidates.find_each(batch_size:) do |blob|
      break if cleanup.limit_reached?
      next if cleanup.references.include?(blob)

      cleanup.delete(blob) do
        # Checked again in the transaction: an attachment made since the
        # query started keeps the image.
        next if blob.attachments.where.not(record_type: "ImageUpload").exists?

        legacy_attachments = blob.attachments.where(record_type: "ImageUpload")
        reason = legacy_attachments.exists? ? "unreferenced_legacy_upload" : "unattached_upload"
        ImageUpload.where(id: legacy_attachments.select(:record_id)).delete_all
        legacy_attachments.delete_all
        reason
      end
    end
  end

  # Blobs older than the grace period attached to nothing but ImageUpload
  # records. Variants are attached to their variant record and go with their
  # original.
  def candidates
    ActiveStorage::Blob
      .where(created_at: ...cleanup.now - GRACE_PERIOD)
      .where.not(id: ActiveStorage::Attachment.where.not(record_type: "ImageUpload").select(:blob_id))
  end

  private

  attr_reader :cleanup
end
