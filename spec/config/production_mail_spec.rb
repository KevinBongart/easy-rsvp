require 'rails_helper'

RSpec.describe 'Production mail URL configuration' do
  it 'preserves the configured deployment host in both email links' do
    # Evaluate the real production configuration against an isolated application.
    # Never boot production, connect to its database, or activate SMTP/S3 adapters.
    deployment_host = 'deployment.example.test'
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('DOMAIN').and_return(deployment_host)
    isolated_application = EasyRsvp::Application.new
    isolated_application.config.action_mailer.default_url_options = { host: deployment_host }
    allow(Rails.application).to receive(:configure) do |&configuration|
      isolated_application.instance_eval(&configuration)
    end
    load Rails.root.join('config/environments/production.rb')

    options = isolated_application.config.action_mailer.default_url_options
    allow(UserMailer).to receive(:default_url_options).and_return(options)
    event = create(:event)
    message = UserMailer.admin_url_request_email('guest@example.test', event)

    pending 'Assessment 1.6: production overrides the deployment mail host with example.com'
    expect(options.fetch(:host)).to eq(deployment_host)
    expect(message.body.decoded).to include("#{deployment_host}/#{event.to_param}")
    expect(message.body.decoded).to include("#{deployment_host}/#{event.to_param}/admin/#{event.admin_token}")
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
