require 'rails_helper'

RSpec.describe 'Images of events marked as spam', type: :request do
  def upload_blob
    ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join('spec/fixtures/files/party.png')),
      filename: 'party.png',
      content_type: 'image/png'
    )
  end

  def embed(event, *blobs)
    event.update!(body: blobs.map { |blob| %(<action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>) }.join)
    event
  end

  def mark(event, source)
    event.update_columns(spam_at: Time.current, spam_source: source, spam_decided_at: Time.current)
  end

  def blob_paths(blob)
    [
      rails_service_blob_path(blob.signed_id, blob.filename),
      rails_service_blob_proxy_path(blob.signed_id, blob.filename),
      "/rails/active_storage/blobs/#{blob.signed_id}/#{blob.filename}"
    ]
  end

  let(:blob) { upload_blob }
  let(:event) { embed(create(:event), blob) }

  it 'serves images of legitimate events' do
    blob_paths(event.body.embeds.first.blob).each do |path|
      get path
      expect(response).to have_http_status(:found).or have_http_status(:ok)
    end
  end

  it 'answers 404 for every blob route once an operator marks the event' do
    mark(event, 'operator')

    blob_paths(blob).each do |path|
      get path
      expect(response).to have_http_status(:not_found), path
    end
  end

  it 'answers 404 for representations of an operator-marked event before processing them' do
    mark(event, 'operator')
    variation_key = ActiveStorage::Variation.encode(resize_to_limit: [ 100, 100 ])

    [
      rails_blob_representation_path(blob.signed_id, variation_key, blob.filename),
      rails_blob_representation_proxy_path(blob.signed_id, variation_key, blob.filename),
      "/rails/active_storage/representations/#{blob.signed_id}/#{variation_key}/#{blob.filename}"
    ].each do |path|
      get path
      expect(response).to have_http_status(:not_found), path
    end
  end

  it 'keeps serving images of automatically flagged events, whose organizers still see them' do
    mark(event, 'automatic')

    get rails_service_blob_path(blob.signed_id, blob.filename)

    expect(response).to have_http_status(:found)
  end

  it 'serves them again after the admin clears the mark' do
    mark(event, 'operator')
    event.update_columns(spam_at: nil, spam_source: 'cleared', spam_decided_at: Time.current)

    get rails_service_blob_path(blob.signed_id, blob.filename)

    expect(response).to have_http_status(:found)
  end

  it 'keeps serving an image also embedded in a legitimate event' do
    mark(event, 'operator')
    embed(create(:event), blob)

    get rails_service_blob_path(blob.signed_id, blob.filename)

    expect(response).to have_http_status(:found)
  end

  it 'keeps serving legacy editor uploads and unattached direct uploads' do
    legacy = ImageUpload.create!(image: { io: File.open(Rails.root.join('spec/fixtures/files/party.png')), filename: 'party.png', content_type: 'image/png' })
    pending_upload = upload_blob
    mark(event, 'operator')

    [ legacy.image.blob, pending_upload ].each do |served|
      get rails_service_blob_path(served.signed_id, served.filename)
      expect(response).to have_http_status(:found)
    end
  end

  it 'still shows them in an admin preview session' do
    mark(event, 'operator')
    get admin_events_path, headers: dashboard_headers

    get rails_service_blob_path(blob.signed_id, blob.filename)

    expect(response).to have_http_status(:found)
  end

  it 'checks the mark within the single blob lookup' do
    blob_path = rails_service_blob_path(event.body.embeds.first.blob.signed_id, blob.filename)

    expect(count_queries { get blob_path }).to eq(1)
    expect(response).to have_http_status(:found)
  end
end
