require 'rails_helper'

RSpec.describe 'Health check' do
  it 'reports that the application booted successfully' do
    get '/up'

    expect(response).to have_http_status(:ok)
  end
end
