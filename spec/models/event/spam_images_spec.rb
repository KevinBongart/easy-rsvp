require 'rails_helper'

RSpec.describe Event::SpamImages, type: :model do
  def upload(bytes = 'image bytes')
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: 'photo.png', content_type: 'image/png')
  end

  def event_with(*blobs)
    create(:event).tap do |event|
      event.update!(body: blobs.map { |blob| %(<action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>) }.join)
    end
  end

  def mark(event, source: :operator, decided: 31.days.ago)
    spam_at = source == :cleared ? nil : decided
    event.update_columns(spam_at:, spam_source: source, spam_decided_at: decided)
  end

  # Flagged by the save-time check or Jev at `flagged`, last edited at `edited`.
  def flag(event, flagged: 31.days.ago, edited: flagged)
    event.update_columns(spam_at: flagged, spam_source: :automatic, updated_at: edited)
  end

  def purge(cleanup = ImageCleanup.new)
    described_class.new(cleanup).purge_expired
    cleanup.result
  end

  def gone?(blob)
    !ActiveStorage::Blob.exists?(blob.id) && !blob.service.exist?(blob.key)
  end

  def kept?(blob)
    ActiveStorage::Blob.exists?(blob.id) && blob.service.exist?(blob.key)
  end

  it 'purges images of events an operator marked more than 30 days ago' do
    first, second = upload('a' * 10), upload('b' * 20)
    event = event_with(first, second)
    mark(event)

    result = purge

    expect(result).to have_attributes(deleted_blobs: { 'operator_spam' => 2 }, deleted_bytes: 30, kept_shared_blobs: 0)
    expect([ first, second ]).to all(satisfy { |blob| gone?(blob) })
    expect(event.reload.body.embeds).to be_empty
    expect(event.title).to be_present
  end

  it 'is idempotent' do
    mark(event_with(upload))

    purge

    expect(purge).to have_attributes(deleted_blobs: {}, deleted_bytes: 0)
  end

  it 'falls back to spam_at for marks without a decision time' do
    blob = upload
    event = event_with(blob)
    event.update_columns(spam_at: 40.days.ago, spam_source: :operator, spam_decided_at: nil)

    purge

    expect(gone?(blob)).to be(true)
  end

  it 'keeps images of recent operator marks, cleared and legitimate events' do
    recent, cleared, legitimate = Array.new(3) { upload }
    mark(event_with(recent), decided: 29.days.ago)
    mark(event_with(cleared), source: :cleared)
    event_with(legitimate)

    expect(purge.deleted_blobs).to be_empty
    expect([ recent, cleared, legitimate ]).to all(satisfy { |blob| kept?(blob) })
  end

  it 'keeps the images when the mark is undone before 30 days' do
    blob = upload
    event = event_with(blob)
    mark(event, decided: 10.days.ago)
    mark(event, source: :cleared, decided: 5.days.ago)

    travel 60.days do
      purge
    end

    expect(kept?(blob)).to be(true)
  end

  describe 'automatic flags' do
    it 'purges images of events flagged and left unedited for more than 30 days' do
      blob = upload('c' * 7)
      event = event_with(blob)
      flag(event)

      expect(purge).to have_attributes(deleted_blobs: { 'automatic_spam' => 1 }, deleted_bytes: 7)
      expect(gone?(blob)).to be(true)
      expect(event.reload).to have_attributes(spam_source: 'automatic', title: be_present)
    end

    it 'counts both the flag and the last edit from the 30-day boundary' do
      now = Time.current
      old, flagged_recently, edited_recently = Array.new(3) { upload }
      flag(event_with(old), flagged: now - 30.days - 1.minute)
      flag(event_with(flagged_recently), flagged: now - 30.days + 1.minute, edited: 60.days.ago)
      flag(event_with(edited_recently), flagged: 60.days.ago, edited: now - 30.days + 1.minute)

      expect(purge(ImageCleanup.new(now:)).deleted_blobs).to eq('automatic_spam' => 1)
      expect(gone?(old)).to be(true)
      expect([ flagged_recently, edited_recently ]).to all(satisfy { |blob| kept?(blob) })
    end

    it 'keeps images of events the organizer edits, whether the flag stays or goes' do
      still_spam, cleared_by_edit = upload, upload
      spam_event = event_with(still_spam)
      spam_event.update!(title: 'Buy Xanax Online No Rx')
      expect(spam_event).to be_flagged_as_spam
      fixed_event = event_with(cleared_by_edit)
      flag(fixed_event)

      travel 31.days do
        spam_event.update!(title: 'Buy Xanax Online No Rx today')
        fixed_event.update!(title: 'Summer picnic')

        expect(purge.deleted_blobs).to be_empty
      end
      expect(spam_event.reload).to be_flagged_as_spam
      expect([ still_spam, cleared_by_edit ]).to all(satisfy { |blob| kept?(blob) })
      expect(fixed_event.reload.spam_source).to be_nil
    end

    it 'keeps images of flags an operator cleared' do
      blob = upload
      event = event_with(blob)
      flag(event)
      mark(event, source: :cleared, decided: 40.days.ago)

      expect(purge.deleted_blobs).to be_empty
      expect(kept?(blob)).to be(true)
    end

    it 'keeps the images when the event is cleared after the run started' do
      blob = upload
      event = event_with(blob)
      flag(event)
      cleanup = ImageCleanup.new
      # Clears the flag after the attachments were loaded, before their transaction.
      allow(cleanup).to receive(:limit_reached?) do
        event.mark_as_not_spam!
        false
      end

      expect(purge(cleanup).deleted_blobs).to be_empty
      expect(event.reload.body.embeds.map(&:blob)).to eq([ blob ])
    end
  end

  it 'detaches but never purges a blob still attached to another record' do
    shared = upload
    spam = event_with(shared)
    legitimate = event_with(shared)
    legacy = ImageUpload.new
    legacy.image.attach(shared)
    legacy.save!
    mark(spam)

    expect(purge).to have_attributes(deleted_blobs: {}, kept_shared_blobs: 1)
    expect(spam.reload.body.embeds).to be_empty
    expect(legitimate.reload.body.embeds.map(&:blob)).to eq([ shared ])
    expect(kept?(shared)).to be(true)
  end

  it 'keeps a blob another description links to by URL' do
    shared = upload
    spam = event_with(shared)
    create(:event, body: %(<img src="/rails/active_storage/blobs/redirect/#{shared.signed_id}/photo.png">))
    mark(spam)

    expect(purge).to have_attributes(deleted_blobs: {}, kept_shared_blobs: 1)
    expect(kept?(shared)).to be(true)
  end

  it 'purges a blob that only other expired spam links to' do
    blob = upload
    mark(event_with(blob))
    mark(create(:event, body: %(<img src="/rails/active_storage/blobs/redirect/#{blob.signed_id}/photo.png">)))

    expect(purge.deleted_blobs).to eq('operator_spam' => 1)
    expect(gone?(blob)).to be(true)
  end

  it 'processes events in batches' do
    blobs = Array.new(3) { upload }
    blobs.each { |blob| mark(event_with(blob)) }

    described_class.new(cleanup = ImageCleanup.new).purge_expired(batch_size: 1)

    expect(cleanup.result.deleted_blobs).to eq('operator_spam' => 3)
  end

  it 'stops at the per-run limit' do
    blobs = Array.new(3) { upload }
    blobs.each { |blob| mark(event_with(blob)) }

    expect(purge(ImageCleanup.new(limit: 2))).to have_attributes(deleted_blobs: { 'operator_spam' => 2 }, limit_reached: true)
    expect(blobs.count { |blob| gone?(blob) }).to eq(2)
  end

  it 'counts retention from the operator decision, not an earlier automatic flag' do
    blob = upload
    event_with(blob).update_columns(spam_at: 60.days.ago, spam_source: :operator, spam_decided_at: 5.days.ago)

    expect(purge.deleted_blobs).to be_empty
    expect(kept?(blob)).to be(true)
  end

  it 'keeps images of an event cleared and marked again recently' do
    blob = upload
    event = event_with(blob)
    mark(event)
    mark(event, source: :cleared, decided: 10.days.ago)
    mark(event, decided: 2.days.ago)

    expect(purge.deleted_blobs).to be_empty
  end

  it 'keeps a blob hidden and purges it on the next run when a run fails midway' do
    blob = upload
    mark(event_with(blob))
    allow_any_instance_of(ActiveStorage::Blob).to receive(:destroy!).and_raise(ActiveRecord::StatementInvalid, 'connection lost')

    expect { purge }.to raise_error(ActiveRecord::StatementInvalid)
    expect(ActiveStorage::Blob.where(Event::SpamImages::HIDDEN_BLOB).exists?(blob.id)).to be(true)

    allow_any_instance_of(ActiveStorage::Blob).to receive(:destroy!).and_call_original
    expect(purge.deleted_blobs).to eq('operator_spam' => 1)
    expect(gone?(blob)).to be(true)
  end

  it 'logs a failed storage delete with its key and carries on' do
    failing, fine = upload('a'), upload('b')
    mark(event_with(failing))
    mark(event_with(fine))
    allow(failing.service).to receive(:delete).and_call_original
    allow(failing.service).to receive(:delete).with(failing.key).and_raise(IOError, 'storage unavailable')
    logger = instance_double(Logger, info: nil, error: nil)

    result = purge(ImageCleanup.new(logger:))

    expect(result).to have_attributes(deleted_blobs: { 'operator_spam' => 1 }, deleted_bytes: 1, failed_deletes: 1)
    expect(result).not_to be_success
    expect(logger).to have_received(:error).with(include(failing.key, 'storage unavailable'))
    expect(gone?(fine)).to be(true)
    expect(ActiveStorage::Blob.exists?(failing.id)).to be(false)
  end
end
