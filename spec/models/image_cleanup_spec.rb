require 'rails_helper'

RSpec.describe ImageCleanup do
  def upload(bytes = 'image bytes')
    travel_to(3.days.ago) do
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: 'photo.png', content_type: 'image/png')
    end
  end

  def spam_event_with(blob)
    create(:event, title: 'Private party at 12 Example Street').tap do |event|
      event.update!(body: %(<action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>))
      event.update_columns(spam_at: 31.days.ago, spam_source: 'operator', spam_decided_at: 31.days.ago)
    end
  end

  let(:log) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(log) }

  it 'deletes expired spam images and orphaned images, logging each blob without event content' do
    spam_blob, orphan = upload('a' * 3), upload('b' * 4)
    spam_event_with(spam_blob)

    result = described_class.run(logger:)

    expect(result).to have_attributes(deleted_blobs: { 'operator_spam' => 1, 'unattached_upload' => 1 }, deleted_bytes: 7, limit_reached: false)
    expect(result).to be_success
    expect(log.string.lines).to eq([
      "images:purge deleted blob_id=#{spam_blob.id} key=#{spam_blob.key} byte_size=3 reason=operator_spam\n",
      "images:purge deleted blob_id=#{orphan.id} key=#{orphan.key} byte_size=4 reason=unattached_upload\n"
    ])
    expect(log.string).not_to include('Example Street', 'photo.png')
    expect(ActiveStorage::Blob.where(id: [ spam_blob.id, orphan.id ])).to be_empty
  end

  it 'previews a run without deleting anything' do
    spam_blob, orphan = upload, upload
    event = spam_event_with(spam_blob)
    image_upload = ImageUpload.new.tap { |record| record.image.attach(orphan) }.tap(&:save!)

    result = described_class.run(dry_run: true, logger:)

    expect(result).to have_attributes(dry_run: true, deleted_blobs: { 'operator_spam' => 1, 'unreferenced_legacy_upload' => 1 })
    expect(result.to_s).to start_with('images:purge dry_run ')
    expect(log.string.lines).to all(start_with('images:purge would delete '))
    expect([ spam_blob, orphan ]).to all(satisfy { |blob| ActiveStorage::Blob.exists?(blob.id) && blob.service.exist?(blob.key) })
    expect(event.reload.body.embeds.map(&:blob)).to eq([ spam_blob ])
    expect(image_upload.reload.image.blob).to eq(orphan)
  end

  it 'shares one limit across spam and orphaned images' do
    spam_event_with(upload)
    upload

    expect(described_class.run(limit: 1)).to have_attributes(deleted_blobs: { 'operator_spam' => 1 }, limit_reached: true)
    expect(described_class.run(limit: 1)).to have_attributes(deleted_blobs: { 'unattached_upload' => 1 })
  end

  it 'caps a run at MAXIMUM_BLOBS_PER_RUN by default' do
    stub_const('ImageCleanup::MAXIMUM_BLOBS_PER_RUN', 1)
    2.times { upload }

    expect(described_class.run).to have_attributes(deleted_blobs: { 'unattached_upload' => 1 }, limit_reached: true)
  end

  it 'logs a failed storage delete, counts it as failed rather than deleted, and continues' do
    failing, fine = upload('a' * 3), upload('b' * 4)
    allow(failing.service).to receive(:delete).and_call_original
    allow(failing.service).to receive(:delete).with(failing.key).and_raise(IOError, 'storage unavailable')

    result = described_class.run(logger:)

    expect(result).to have_attributes(deleted_blobs: { 'unattached_upload' => 1 }, deleted_bytes: 4, failed_deletes: 1)
    expect(result).not_to be_success
    expect(log.string).to include("could not delete stored file blob_id=#{failing.id} key=#{failing.key}: IOError: storage unavailable")
    expect(fine.service.exist?(fine.key)).to be(false)
  end

  it 'counts blobs whose file delete failed towards the limit, since their rows are gone' do
    2.times { upload }
    allow_any_instance_of(ActiveStorage::Blob).to receive(:delete).and_raise(IOError, 'storage unavailable')

    result = described_class.run(limit: 1, logger:)

    expect(result).to have_attributes(deleted_blobs: {}, failed_deletes: 1, limit_reached: true)
    expect(ActiveStorage::Blob.count).to eq(1)
  end

  it 'reads every description before taking any row lock' do
    spam_event_with(upload)
    baseline = ActiveRecord::Base.connection.open_transactions
    depths = []
    allow(ImageReferences).to receive(:in_descriptions_of).and_wrap_original do |original, *args, **options|
      depths << ActiveRecord::Base.connection.open_transactions
      original.call(*args, **options)
    end

    expect(described_class.run.deleted_blobs).to eq('operator_spam' => 1)
    expect(depths).to eq([ baseline ])
  end

  it 'refuses, in the database, to delete a blob an attachment points at' do
    blob = upload
    spam_event_with(blob)

    expect { ActiveStorage::Blob.where(id: blob.id).delete_all }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'keeps a blob that a concurrent save attached between the check and the delete' do
    blob = upload
    allow_any_instance_of(ActiveStorage::Blob).to receive(:destroy!).and_raise(ActiveRecord::InvalidForeignKey)

    result = described_class.run(logger:)

    expect(result).to have_attributes(deleted_blobs: {}, kept_shared_blobs: 1, failed_deletes: 0)
    expect(ActiveStorage::Blob.exists?(blob.id) && blob.service.exist?(blob.key)).to be(true)
    expect(log.string).to be_empty
  end

  it 'summarizes a run on one line' do
    result = described_class::Result.new(dry_run: false, deleted_blobs: { 'automatic_spam' => 2, 'unattached_upload' => 1 },
      deleted_bytes: 400, kept_shared_blobs: 1, failed_deletes: 0, limit_reached: false)

    expect(result.to_s).to eq('images:purge operator_spam=0 automatic_spam=2 unattached_upload=1 unreferenced_legacy_upload=0 ' \
      'deleted_bytes=400 kept_shared_blobs=1 failed_deletes=0 limit_reached=false')
  end
end
