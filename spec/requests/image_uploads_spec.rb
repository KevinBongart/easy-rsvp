require 'rails_helper'

RSpec.describe 'Image upload integration', type: :request do
  it 'accepts an image and returns a working download URL with its original bytes' do
    expect do
      post image_uploads_path(format: :json), params: { image_upload: { image: uploaded_image } }
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
      post image_uploads_path(format: :json), params: { image_upload: { image: uploaded_image } }
    end.not_to change(Event, :count)
    expect(response).to have_http_status(:ok)
  end

  it 'does not accept mass-assignment of an upload record ID' do
    post image_uploads_path(format: :json), params: { image_upload: { image: uploaded_image, id: 12345678 } }
    expect(ImageUpload.order(:id).last.id).not_to eq(12345678)
  end

  it 'rejects a missing upload parameter object without creating records' do
    expect { post image_uploads_path(format: :json), params: {} }.not_to change(ImageUpload, :count)
    expect(response).to have_http_status(:bad_request)
  end
end
