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

  describe 'rate limit' do
    let(:ip) { '203.0.113.7' }

    def upload(from: ip, **overrides)
      post '/rails/active_storage/direct_uploads',
        params: { blob: valid_attributes.merge(overrides) }, as: :json, env: { 'REMOTE_ADDR' => from }
    end

    it 'refuses uploads past the burst limit with a JSON error' do
      RichTextDirectUploadsController::BURST_LIMIT.times { upload }
      expect(response).to have_http_status(:ok)

      expect { upload }.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body).to eq('error' => RichTextDirectUploadsController::LIMITED_MESSAGE)
    end

    it 'counts refused declarations too' do
      RichTextDirectUploadsController::BURST_LIMIT.times { upload(content_type: 'application/pdf') }

      upload
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'counts each client separately' do
      RichTextDirectUploadsController::BURST_LIMIT.times { upload }

      upload
      expect(response).to have_http_status(:too_many_requests)
      upload(from: '198.51.100.20')
      expect(response).to have_http_status(:ok)
    end

    it 'allows bursts again after the window but caps uploads per day' do
      start = Time.zone.local(2026, 11, 20, 0, 0)
      bursts = RichTextDirectUploadsController::DAILY_LIMIT / RichTextDirectUploadsController::BURST_LIMIT

      bursts.times do |n|
        travel_to(start + (n * 11).minutes) do
          RichTextDirectUploadsController::BURST_LIMIT.times { upload }
          expect(response).to have_http_status(:ok)
        end
      end

      travel_to(start + (bursts * 11).minutes) do
        upload
        expect(response).to have_http_status(:too_many_requests)
      end
      travel_to(start + RichTextDirectUploadsController::DAILY_WINDOW + 1.second) do
        upload
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
