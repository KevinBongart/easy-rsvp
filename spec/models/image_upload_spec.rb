require 'rails_helper'

RSpec.describe ImageUpload, type: :model do
  def attach_image(upload)
    upload.image.attach(io: File.open(Rails.root.join('spec/fixtures/files/party.png')), filename: 'party.png', content_type: 'image/png')
  end

  def create_upload(**attributes)
    upload = described_class.new(attributes)
    attach_image(upload)
    upload.save!
    upload
  end

  it 'persists the image and original bytes to test disk storage' do
    upload = described_class.new
    attach_image(upload)
    upload.save!
    expect(upload.reload.image).to be_attached
    expect(upload.image.blob.service_name).to eq('test')
    expect(upload.image.download).to eq(File.binread(Rails.root.join('spec/fixtures/files/party.png')))
  end

  it 'purges an attachment and its backing file' do
    upload = described_class.new
    attach_image(upload)
    upload.save!
    blob = upload.image.blob
    upload.image.purge
    expect(upload.reload.image).not_to be_attached
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
    expect(blob.service.exist?(blob.key)).to be(false)
  end

  it 'requires a file' do
    expect(described_class.new).not_to be_valid
  end

  it 'rejects a non-image attachment' do
    upload = described_class.new
    upload.image.attach(io: File.open(Rails.root.join('spec/fixtures/files/notes.txt')), filename: 'notes.txt', content_type: 'text/plain')
    expect(upload).not_to be_valid
  end

  [10.megabytes, 10.megabytes + 1].each do |size|
    it "enforces the 10 MB limit for a #{size}-byte image" do
      bytes = File.binread(Rails.root.join('spec/fixtures/files/party.png')).ljust(size, "\0")
      upload = described_class.new
      upload.image.attach(io: StringIO.new(bytes), filename: 'large.png', content_type: 'image/png')
      expect(upload.valid?).to eq(size <= 10.megabytes)
      expect(upload.errors[:image]).to include('must be 10 MB or smaller') if size > 10.megabytes
    end
  end

  it 'finds only managed, unowned uploads older than 24 hours for cleanup' do
    historical = create_upload
    recent = create_upload(upload_session_digest: described_class.digest_token('recent'))
    abandoned = create_upload(upload_session_digest: described_class.digest_token('abandoned'))
    owned = create_upload(event: create(:event), upload_session_digest: nil)
    abandoned.update_column(:created_at, 24.hours.ago - 1.second)
    owned.update_column(:created_at, 2.days.ago)

    expect(described_class.abandoned).to contain_exactly(abandoned)
    expect(described_class.abandoned).not_to include(historical, recent, owned)
  end

  it 'purges abandoned managed records, blobs, and disk files' do
    upload = create_upload(upload_session_digest: described_class.digest_token('abandoned'))
    upload.update_column(:created_at, 24.hours.ago - 1.second)
    blob = upload.image.blob

    expect(described_class.purge_abandoned!).to eq(1)

    expect(described_class.exists?(upload.id)).to be(false)
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
    expect(blob.service.exist?(blob.key)).to be(false)
  end

  it 'removes owned upload records and their blobs when the event is deleted' do
    event = create(:event)
    upload = create_upload(event: event)
    blob = upload.image.blob

    perform_enqueued_jobs { event.destroy! }

    expect(described_class.exists?(upload.id)).to be(false)
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
  end

end
