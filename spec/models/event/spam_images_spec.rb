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

  def mark(event, source: 'operator', decided: 31.days.ago)
    spam_at = source == 'cleared' ? nil : decided
    event.update_columns(spam_at:, spam_source: source, spam_decided_at: decided)
  end

  def gone?(blob)
    !ActiveStorage::Blob.exists?(blob.id) && !blob.service.exist?(blob.key)
  end

  it 'purges images of events an operator marked more than 30 days ago' do
    first, second = upload('a' * 10), upload('b' * 20)
    event = event_with(first, second)
    mark(event)

    result = described_class.purge_expired

    expect(result).to have_attributes(events: 1, purged_blobs: 2, purged_bytes: 30, kept_shared_blobs: 0)
    expect([ first, second ]).to all(satisfy { |blob| gone?(blob) })
    expect(event.reload.body.embeds).to be_empty
    expect(event.title).to be_present
  end

  it 'is idempotent' do
    mark(event_with(upload))

    described_class.purge_expired

    expect(described_class.purge_expired).to have_attributes(events: 0, purged_blobs: 0, purged_bytes: 0)
  end

  it 'falls back to spam_at for marks without a decision time' do
    blob = upload
    event = event_with(blob)
    event.update_columns(spam_at: 40.days.ago, spam_source: 'operator', spam_decided_at: nil)

    described_class.purge_expired

    expect(gone?(blob)).to be(true)
  end

  it 'keeps images of recent operator marks, automatic marks, cleared and legitimate events' do
    recent, automatic, cleared, legitimate = Array.new(4) { upload }
    mark(event_with(recent), decided: 29.days.ago)
    mark(event_with(automatic), source: 'automatic')
    mark(event_with(cleared), source: 'cleared')
    event_with(legitimate)

    expect(described_class.purge_expired).to have_attributes(events: 0, purged_blobs: 0)
    expect([ recent, automatic, cleared, legitimate ].map { |blob| ActiveStorage::Blob.exists?(blob.id) }).to all(be(true))
  end

  it 'keeps the images when the mark is undone before 30 days' do
    blob = upload
    event = event_with(blob)
    mark(event, decided: 10.days.ago)
    mark(event, source: 'cleared', decided: 5.days.ago)

    travel 60.days do
      described_class.purge_expired
    end

    expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
  end

  it 'detaches but never purges a blob still attached to another record' do
    shared = upload
    spam = event_with(shared)
    legitimate = event_with(shared)
    legacy = ImageUpload.new
    legacy.image.attach(shared)
    legacy.save!
    mark(spam)

    expect(described_class.purge_expired).to have_attributes(events: 1, purged_blobs: 0, kept_shared_blobs: 1)
    expect(spam.reload.body.embeds).to be_empty
    expect(legitimate.reload.body.embeds.map(&:blob)).to eq([ shared ])
    expect(shared.service.exist?(shared.key)).to be(true)
  end

  it 'processes events in batches' do
    blobs = Array.new(3) { upload }
    blobs.each { |blob| mark(event_with(blob)) }

    expect(described_class.purge_expired(batch_size: 1)).to have_attributes(events: 3, purged_blobs: 3)
  end

  it 'summarizes the run on one line without personal data' do
    result = described_class::Result.new(events: 2, purged_blobs: 3, purged_bytes: 400, kept_shared_blobs: 1, failed_deletes: 0)

    expect(result.to_s).to eq('spam:purge_images events=2 purged_blobs=3 purged_bytes=400 kept_shared_blobs=1 failed_deletes=0')
    expect(result).to be_success
  end

  it 'counts retention from the operator decision, not an earlier automatic flag' do
    blob = upload
    event_with(blob).update_columns(spam_at: 60.days.ago, spam_source: 'operator', spam_decided_at: 5.days.ago)

    expect(described_class.purge_expired).to have_attributes(events: 0, purged_blobs: 0)
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
  end

  it 'keeps images of an event cleared and marked again recently' do
    blob = upload
    event = event_with(blob)
    mark(event)
    mark(event, source: 'cleared', decided: 10.days.ago)
    mark(event, decided: 2.days.ago)

    expect(described_class.purge_expired).to have_attributes(purged_blobs: 0)
  end

  it 'keeps a blob hidden and purges it on the next run when a run fails midway' do
    blob = upload
    mark(event_with(blob))
    allow_any_instance_of(ActiveStorage::Blob).to receive(:destroy!).and_raise(ActiveRecord::StatementInvalid, 'connection lost')

    expect { described_class.purge_expired }.to raise_error(ActiveRecord::StatementInvalid)
    expect(ActiveStorage::Blob.where(Event::SpamImages::HIDDEN_BLOB).exists?(blob.id)).to be(true)

    allow_any_instance_of(ActiveStorage::Blob).to receive(:destroy!).and_call_original
    expect(described_class.purge_expired).to have_attributes(purged_blobs: 1)
    expect(gone?(blob)).to be(true)
  end

  it 'logs a failed storage delete with its key and carries on' do
    failing, fine = upload('a'), upload('b')
    mark(event_with(failing))
    mark(event_with(fine))
    allow(failing.service).to receive(:delete).and_call_original
    allow(failing.service).to receive(:delete).with(failing.key).and_raise(IOError, 'storage unavailable')
    logger = instance_double(Logger, error: nil)

    result = described_class.purge_expired(logger:)

    expect(result).to have_attributes(purged_blobs: 1, failed_deletes: 1)
    expect(result).not_to be_success
    expect(logger).to have_received(:error).with(include(failing.key, 'storage unavailable'))
    expect(gone?(fine)).to be(true)
    expect(ActiveStorage::Blob.exists?(failing.id)).to be(false)
  end
end
