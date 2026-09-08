require 'rails_helper'

RSpec.describe UserMailer, type: :mailer do
  let(:event) { create(:event, title: 'Dinner & games') }
  let(:message) { described_class.admin_url_request_email('guest@example.test', event) }

  it 'addresses the recipient and identifies the event in the subject' do
    expect(message.to).to eq(['guest@example.test'])
    expect(message.from).to eq(['info@easy-rsvp.com'])
    expect(message.subject).to eq('Easy RSVP: Dinner & games')
  end

  it 'contains the exact organizer and public URLs' do
    urls = Rails.application.routes.url_helpers
    expect(message.body.decoded).to include(urls.event_admin_url(event, event.admin_token, host: 'example.com'))
    expect(message.body.decoded).to include(urls.event_url(event, host: 'example.com'))
  end

  it 'does not send a message merely by constructing it' do
    expect { message.body.decoded }.not_to change(ActionMailer::Base.deliveries, :size)
  end

  it 'delivers locally through the test adapter' do
    expect { message.deliver_now }.to change(ActionMailer::Base.deliveries, :size).by(1)
    expect(ActionMailer::Base.delivery_method).to eq(:test)
  end
end
