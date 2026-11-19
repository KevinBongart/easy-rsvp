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
    result = described_class::Result.new(events: 2, purged_blobs: 3, purged_bytes: 400, kept_shared_blobs: 1)

    expect(result.to_s).to eq('spam:purge_images events=2 purged_blobs=3 purged_bytes=400 kept_shared_blobs=1')
  end
end
