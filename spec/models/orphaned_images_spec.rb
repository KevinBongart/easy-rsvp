require 'rails_helper'

RSpec.describe OrphanedImages, type: :model do
  def upload(bytes = 'image bytes', at: 3.days.ago)
    travel_to(at) do
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: 'photo.png', content_type: 'image/png')
    end
  end

  def legacy_upload(at: 3.days.ago)
    blob = upload(at:)
    travel_to(at) { ImageUpload.new.tap { |record| record.image.attach(blob) }.tap(&:save!) }
  end

  def purge(cleanup = ImageCleanup.new)
    described_class.purge(cleanup)
    cleanup.result
  end

  def gone?(blob)
    !ActiveStorage::Blob.exists?(blob.id) && !blob.service.exist?(blob.key)
  end

  def kept?(blob)
    ActiveStorage::Blob.exists?(blob.id) && blob.service.exist?(blob.key)
  end

  def url(blob) = "/rails/active_storage/blobs/redirect/#{blob.signed_id}/photo.png"

  it 'deletes direct uploads that never made it into an event, after the grace period' do
    now = Time.current
    old = upload('a' * 5, at: now - 2.days - 1.minute)
    recent = upload(at: now - 2.days + 1.minute)

    expect(purge(ImageCleanup.new(now:))).to have_attributes(deleted_blobs: { 'unattached_upload' => 1 }, deleted_bytes: 5)
    expect(gone?(old)).to be(true)
    expect(kept?(recent)).to be(true)
  end

  it 'deletes legacy uploads no description links to, with their ImageUpload rows' do
    image_upload = legacy_upload
    blob = image_upload.image.blob

    expect(purge.deleted_blobs).to eq('unreferenced_legacy_upload' => 1)
    expect(gone?(blob)).to be(true)
    expect(ImageUpload.exists?(image_upload.id)).to be(false)
    expect(ActiveStorage::Attachment.where(record_type: 'ImageUpload')).to be_empty
  end

  it 'keeps legacy uploads a description links to' do
    image_upload = legacy_upload
    create(:event, body: %(<img src="#{url(image_upload.image.blob)}">))

    expect(purge.deleted_blobs).to be_empty
    expect(kept?(image_upload.image.blob)).to be(true)
    expect(ImageUpload.exists?(image_upload.id)).to be(true)
  end

  it 'keeps a legacy upload linked from expired spam that is marked "Not spam" during the run' do
    image_upload = legacy_upload
    event = create(:event, body: %(<img src="#{url(image_upload.image.blob)}">))
    event.update_columns(spam_at: 31.days.ago, spam_source: 'operator', spam_decided_at: 31.days.ago)
    cleanup = ImageCleanup.new
    cleanup.read_descriptions
    event.update_columns(spam_at: nil, spam_source: 'cleared')

    blob = image_upload.image.blob

    expect(purge(cleanup)).to have_attributes(deleted_blobs: {}, kept_shared_blobs: 1)
    expect(kept?(blob)).to be(true)
  end

  it 'deletes a legacy upload linked only from spam still expired' do
    image_upload = legacy_upload
    create(:event, body: %(<img src="#{url(image_upload.image.blob)}">))
      .update_columns(spam_at: 31.days.ago, spam_source: 'operator', spam_decided_at: 31.days.ago)

    expect(purge.deleted_blobs).to eq('unreferenced_legacy_upload' => 1)
    expect(gone?(image_upload.image.blob)).to be(true)
  end

  it 'never considers images embedded in events' do
    blob = upload
    event = create(:event)
    event.update!(body: %(<action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>))

    expect(described_class.candidates).not_to include(blob)
    expect(purge.deleted_blobs).to be_empty
  end

  it 'keeps images referenced from spam until its images expire' do
    recent, expired = upload, upload
    create(:event, body: %(<img src="#{url(recent)}">)).update_columns(spam_at: 29.days.ago, spam_source: 'operator')
    create(:event, body: %(<img src="#{url(expired)}">)).update_columns(spam_at: 31.days.ago, spam_source: 'operator')

    expect(purge.deleted_blobs).to eq('unattached_upload' => 1)
    expect(kept?(recent)).to be(true)
    expect(gone?(expired)).to be(true)
  end

  it 'deletes the variants of a deleted image' do
    blob = upload
    variant = ActiveStorage::VariantRecord.create!(blob:, variation_digest: 'digest')
    variant.image.attach(io: StringIO.new('small'), filename: 'photo.png', content_type: 'image/png')
    variant_blob = variant.image.blob
    logger = instance_double(Logger, info: nil)

    expect(purge(ImageCleanup.new(logger:))).to have_attributes(deleted_blobs: { 'unattached_upload' => 1 }, deleted_bytes: 16)
    expect([ blob, variant_blob ]).to all(satisfy { |each_blob| gone?(each_blob) })
    expect(ActiveStorage::VariantRecord.exists?(variant.id)).to be(false)
    expect(logger).to have_received(:info).with(include("blob_id=#{variant_blob.id}", 'reason=variant'))
  end

  it 'keeps a legacy upload embedded since the descriptions were scanned' do
    image_upload = legacy_upload
    blob = image_upload.image.blob
    cleanup = ImageCleanup.new
    allow(cleanup).to receive(:references).and_wrap_original do |original|
      original.call.tap { create(:event, body: %(<action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>)) }
    end

    expect(purge(cleanup).deleted_blobs).to be_empty
    expect(kept?(blob)).to be(true)
    expect(ImageUpload.exists?(image_upload.id)).to be(true)
  end

  it 'stops at the per-run limit and continues on the next run' do
    blobs = Array.new(3) { upload }

    expect(purge(ImageCleanup.new(limit: 2))).to have_attributes(deleted_blobs: { 'unattached_upload' => 2 }, limit_reached: true)
    expect(purge(ImageCleanup.new(limit: 2))).to have_attributes(deleted_blobs: { 'unattached_upload' => 1 }, limit_reached: false)
    expect(blobs).to all(satisfy { |blob| gone?(blob) })
  end
end
