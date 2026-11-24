# Images embedded in the descriptions of spam events.
#
# Images of operator marks are no longer served (see HidesOperatorSpamImages)
# and are deleted SPAM_IMAGE_RETENTION after the mark by `bin/rails images:purge`
# (ImageCleanup), which Dokku runs daily. Undoing the mark ("Not spam") before
# then keeps them. Images of automatic flags stay visible, since their
# organizers still see their pages, and are deleted once the flag is
# SPAM_IMAGE_RETENTION old and the event has not been edited for as long
# (Event.spam_images_expired).
#
# Only Action Text embeds count here. Legacy editor uploads (ImageUpload)
# stopped in September 2026, before the spam wave; their blobs belong to
# ImageUpload records, are never hidden, and are deleted by OrphanedImages once
# no description references them.
class Event::SpamImages
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

  def initialize(cleanup)
    @cleanup = cleanup
  end

  # Deletes the embeds of expired events, one attachment at a time (see
  # ImageCleanup#delete). A blob also attached elsewhere, or referenced from
  # another description, is detached and kept.
  def purge_expired(batch_size: 100)
    cleanup.read_descriptions
    rich_texts = ActionText::RichText.where(record_type: "Event", name: "body", record_id: expired_events.select(:id))
    attachments = ActiveStorage::Attachment
      .where(record_type: "ActionText::RichText", name: "embeds", record_id: rich_texts.select(:id))
      .includes(:blob, :record)

    attachments.find_each(batch_size:) do |attachment|
      break if cleanup.limit_reached?

      cleanup.delete(attachment.blob) do
        # Checked again under the event's row lock: an edit or a "Not spam"
        # click since the query started keeps the images.
        event = expired_events.lock.find_by(id: attachment.record.record_id)
        next unless event

        attachment.delete
        "#{event.spam_source}_spam"
      end
    end
  end

  private

  attr_reader :cleanup

  def expired_events = Event.spam_images_expired(cleanup.now)
end
