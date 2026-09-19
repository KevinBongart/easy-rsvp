require 'rails_helper'

RSpec.describe 'Organizer link email requests', type: :request do
  it 'keeps organizer-link email delivery unavailable while the feature is reworked' do
    event = create(:event)
    previous_path = "/#{event.to_param}/admin/#{event.admin_token}/email_requests"

    expect do
      post previous_path, params: { email: 'guest@example.test' }
    end.not_to change(ActionMailer::Base.deliveries, :size)

    expect(response).to have_http_status(:not_found)
  end
end
