require 'rails_helper'

RSpec.describe ImageUpload, type: :model do
  def attach_image(upload)
    upload.image.attach(io: File.open(Rails.root.join('spec/fixtures/files/party.png')), filename: 'party.png', content_type: 'image/png')
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
    pending 'Assessment 2.4: ImageUpload has no attachment presence validation'
    expect(described_class.new).not_to be_valid
  end

  it 'rejects a non-image attachment' do
    pending 'Assessment 2.4: ImageUpload has no content-type validation'
    upload = described_class.new
    upload.image.attach(io: File.open(Rails.root.join('spec/fixtures/files/notes.txt')), filename: 'notes.txt', content_type: 'text/plain')
    expect(upload).not_to be_valid
  end
end
