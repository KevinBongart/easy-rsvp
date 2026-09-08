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

  it 'propagates delivery failure without changing the event or recording delivered mail' do
    delivery = UserMailer.admin_url_request_email('guest@example.test', event)
    allow(UserMailer).to receive(:admin_url_request_email).with('guest@example.test', event).and_return(delivery)
    allow(delivery).to receive(:deliver_now).and_raise(Net::SMTPServerBusy.new('Service temporarily unavailable'))
    original = event.reload.attributes

    expect do
      post event_admin_email_requests_path(event, event.admin_token), params: { email: 'guest@example.test' }
    end.to raise_error(Net::SMTPServerBusy)
    expect(event.reload.attributes).to eq(original)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

end
