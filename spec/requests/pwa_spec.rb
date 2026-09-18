require 'rails_helper'

RSpec.describe 'PWA manifest', type: :request do
  it 'serves the application manifest as JSON' do
    get pwa_manifest_path(format: :json)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/json')
    expect(response.parsed_body).to include(
      'name' => 'Easy RSVP',
      'start_url' => '/',
      'display' => 'standalone'
    )
  end

  it 'returns not found for unsupported manifest formats' do
    get '/manifest.js'

    expect(response).to have_http_status(:not_found)
  end
end
