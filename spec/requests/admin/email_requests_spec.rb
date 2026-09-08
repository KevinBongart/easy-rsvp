require 'rails_helper'

RSpec.describe 'Organizer link email requests', type: :request do
  let(:event) { create(:event) }

  it 'sends exactly one email for an authorized request' do
    expect do
      post event_admin_email_requests_path(event, event.admin_token), params: { email: 'guest@example.test' }
    end.to change(ActionMailer::Base.deliveries, :size).by(1)
    expect(ActionMailer::Base.deliveries.last.to).to eq(['guest@example.test'])
    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
    expect(flash[:notice]).to include('guest@example.test')
  end

  [nil, '', '  '].each do |email|
    it "does not deliver for a blank email (#{email.inspect})" do
      expect do
        post event_admin_email_requests_path(event, event.admin_token), params: { email: email }
      end.not_to change(ActionMailer::Base.deliveries, :size)
      expect(flash[:alert]).to eq('Please enter your email address')
    end
  end

  it 'does not send private links to someone with the wrong token' do
    expect do
      post event_admin_email_requests_path(event, 'wrong'), params: { email: 'guest@example.test' }
    end.not_to change(ActionMailer::Base.deliveries, :size)
    expect(response).to have_http_status(:not_found)
  end
end
