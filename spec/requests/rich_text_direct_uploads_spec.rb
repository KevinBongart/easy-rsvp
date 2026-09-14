require 'rails_helper'

RSpec.describe 'Rich text direct uploads', type: :request do
  let(:valid_attributes) do
    bytes = File.binread(Rails.root.join('spec/fixtures/files/party.png'))

    {
      filename: 'party.png',
      content_type: 'image/png',
      byte_size: bytes.bytesize,
      checksum: Digest::MD5.base64digest(bytes)
    }
  end

  it 'creates a direct-upload blob for an allowed image declaration' do
    expect do
      post '/rails/active_storage/direct_uploads', params: { blob: valid_attributes }, as: :json
    end.to change(ActiveStorage::Blob, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('signed_id', 'direct_upload')
  end

  it 'rejects unsupported declared content types before creating a blob' do
    expect do
      post '/rails/active_storage/direct_uploads',
        params: { blob: valid_attributes.merge(content_type: 'application/pdf') },
        as: :json
    end.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'rejects empty and oversized declarations before creating a blob' do
    [ 0, RichTextDirectUploadsController::MAXIMUM_SIZE + 1 ].each do |byte_size|
      expect do
        post '/rails/active_storage/direct_uploads',
          params: { blob: valid_attributes.merge(byte_size:) },
          as: :json
      end.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
