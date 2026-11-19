# Images embedded in the description of events an operator marked as spam.
#
# Such images are no longer served (see HidesOperatorSpamImages) and are
# deleted RETENTION after the mark by `bin/rails spam:purge_images`, which
# Dokku runs daily. Undoing the mark ("Not spam") before then keeps them.
#
# Only Action Text embeds count. Legacy editor uploads (ImageUpload) stopped in
# September 2026, before the spam wave; their blobs belong to ImageUpload
# records and are never hidden or purged here.
module Event::SpamImages
  RETENTION = 30.days

  # SQL condition on active_storage_blobs: the blob is embedded in an
  # operator-marked event's description, and in nothing else. A blob also
  # attached to another record (for instance a legitimate event's description)
  # stays visible. Both subqueries use the blob_id index.
  HIDDEN_BLOB = <<~SQL.squish.freeze
    EXISTS (
      SELECT 1 FROM active_storage_attachments spam_attachments
      JOIN action_text_rich_texts spam_texts
        ON spam_texts.id = spam_attachments.record_id
        AND spam_texts.record_type = 'Event' AND spam_texts.name = 'body'
      JOIN events spam_events
        ON spam_events.id = spam_texts.record_id AND spam_events.spam_source = 'operator'
      WHERE spam_attachments.blob_id = active_storage_blobs.id
        AND spam_attachments.record_type = 'ActionText::RichText'
        AND spam_attachments.name = 'embeds'
    )
    AND NOT EXISTS (
      SELECT 1 FROM active_storage_attachments other_attachments
      LEFT JOIN action_text_rich_texts other_texts
        ON other_attachments.record_type = 'ActionText::RichText'
        AND other_attachments.name = 'embeds'
        AND other_texts.id = other_attachments.record_id
        AND other_texts.record_type = 'Event' AND other_texts.name = 'body'
      LEFT JOIN events other_events ON other_events.id = other_texts.record_id
      WHERE other_attachments.blob_id = active_storage_blobs.id
        AND other_events.spam_source IS DISTINCT FROM 'operator'
    )
  SQL

  Result = Data.define(:events, :purged_blobs, :purged_bytes, :kept_shared_blobs) do
    def to_s
      "spam:purge_images events=#{events} purged_blobs=#{purged_blobs} " \
        "purged_bytes=#{purged_bytes} kept_shared_blobs=#{kept_shared_blobs}"
    end
  end

  module_function

  # Events whose operator mark is older than RETENTION. spam_decided_at was
  # backfilled from spam_at for older marks; spam_at covers any gap.
  def expired_events(now: Time.current)
    Event.where(spam_source: "operator")
      .where("COALESCE(events.spam_decided_at, events.spam_at) < ?", now - RETENTION)
  end

  # Deletes the embeds of expired events: the attachment rows always, and each
  # blob with its file once nothing else is attached to it. Runs in a one-off
  # container, so it purges synchronously. Safe to run repeatedly: processed
  # attachments are gone, so a second run finds nothing.
  def purge_expired(now: Time.current, batch_size: 100)
    rich_texts = ActionText::RichText.where(record_type: "Event", name: "body", record_id: expired_events(now:).select(:id))
    attachments = ActiveStorage::Attachment
      .where(record_type: "ActionText::RichText", name: "embeds", record_id: rich_texts.select(:id))
      .includes(:blob)

    events = Set.new
    purged_blobs = purged_bytes = kept_shared_blobs = 0

    attachments.find_each(batch_size:) do |attachment|
      events << attachment.record_id
      blob = attachment.blob
      attachment.delete
      next unless blob

      if blob.attachments.exists?
        kept_shared_blobs += 1
      else
        blob.purge
        purged_blobs += 1
        purged_bytes += blob.byte_size
      end
    end

    Result.new(events: events.size, purged_blobs:, purged_bytes:, kept_shared_blobs:)
  end
end
