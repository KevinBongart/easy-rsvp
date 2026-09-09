require 'rails_helper'

RSpec.describe 'Image upload integration', type: :request do
  def upload_token
    get root_path
    Nokogiri::HTML(response.body).at_css('trix-editor')['data-upload-token']
  end

  def upload_params(image: uploaded_image, token: upload_token, **extra)
    { image_upload: { image: image, token: token }.merge(extra) }
  end

  it 'accepts an image and returns a working download URL with its original bytes' do
    expect do
      post image_uploads_path(format: :json), params: upload_params
    end.to change(ImageUpload, :count).by(1).and change(ActiveStorage::Blob, :count).by(1)
    expect(response).to have_http_status(:ok)
    url = response.parsed_body.fetch('url')
    get URI(url).request_uri
    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq(File.binread(Rails.root.join('spec/fixtures/files/party.png')))
    expect(response.media_type).to eq('image/png')
  end

  it 'does not require an event to have been saved before uploading editor content' do
    expect do
      post image_uploads_path(format: :json), params: upload_params
    end.not_to change(Event, :count)
    expect(response).to have_http_status(:ok)
  end

  it 'does not accept mass-assignment of an upload record ID' do
    post image_uploads_path(format: :json), params: upload_params(id: 12345678)
    expect(ImageUpload.order(:id).last.id).not_to eq(12345678)
  end

  it 'requires a capability issued by an event editor' do
    expect do
      post image_uploads_path(format: :json), params: upload_params(token: 'not-issued')
    end.not_to change(ImageUpload, :count)
    expect(response).to have_http_status(:forbidden)
    expect(ActiveStorage::Blob.count).to eq(0)
  end

  it 'rejects a missing upload parameter object without creating records' do
    expect { post image_uploads_path(format: :json), params: {} }.not_to change(ImageUpload, :count)
    expect(response).to have_http_status(:bad_request)
  end

  it 'rejects a non-image even when its submitted MIME type claims it is a PNG' do
    file = fixture_file_upload(Rails.root.join('spec/fixtures/files/notes.txt'), 'image/png')
    expect do
      post image_uploads_path(format: :json), params: upload_params(image: file)
    end.not_to change(ImageUpload, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('image')).to be_present
    expect(ActiveStorage::Blob.count).to eq(0)
  end

  it 'rejects a blank file without leaving an upload record behind' do
    expect do
      post image_uploads_path(format: :json), params: upload_params(image: '')
    end.not_to change(ImageUpload, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'disables the unused Active Storage direct-upload endpoint' do
    expect do
      post rails_active_storage_direct_uploads_path, params: {
        blob: { filename: 'party.png', byte_size: 100, checksum: 'unused', content_type: 'image/png' }
      }
    end.not_to change(ActiveStorage::Blob, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'limits upload bursts by IP address' do
    token = upload_token
    20.times do
      post image_uploads_path(format: :json), params: upload_params(token: token)
      expect(response).to have_http_status(:ok)
    end

    expect do
      post image_uploads_path(format: :json), params: upload_params(token: token)
    end.not_to change(ImageUpload, :count)
    expect(response).to have_http_status(:too_many_requests)
  end
end
