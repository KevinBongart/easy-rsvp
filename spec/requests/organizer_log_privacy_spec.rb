require 'rails_helper'
require 'stringio'

RSpec.describe 'Organizer log privacy', type: :request do
  it 'redacts organizer paths without changing authorization or redirects' do
    event = create(:event)
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    original = Rails.logger.respond_to?(:broadcasts) ? Rails.logger.broadcasts.first : Rails.logger
    logger.formatter = original.formatter
    allow(Rails).to receive(:logger).and_return(logger)
    get event_admin_path(event, event.admin_token)
    expect(response).to have_http_status(:ok)
    expect(output.string).to include('Started GET')
    expect(output.string.include?(event.admin_token)).to be(false)
    expect(output.string).to include('[FILTERED]')
    post toggle_publish_event_admin_path(event, event.admin_token)
    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
    expect(event.reload.published?).to be(false)
    expect(output.string.include?(event.admin_token)).to be(false)
  end

  it 'labels Scout traces without the organizer token' do
    event = create(:event)
    scout_request = ScoutApm::TrackedRequest.new(ScoutApm::Agent.instance.context, ScoutApm::FakeStore.new)
    scout_request.annotate_request(uri: event_admin_path(event, event.admin_token))
    Thread.current[:scout_request] = scout_request

    get event_admin_path(event, event.admin_token)

    expect(response).to have_http_status(:ok)
    expect(scout_request.annotations[:uri]).to eq("/#{event.to_param}/admin/[FILTERED]")
  ensure
    Thread.current[:scout_request] = nil
  end

  it 'leaves error reports to Honeybadger instead of Scout' do
    expect(ScoutApm::Agent.instance.context.config.value('errors_enabled')).to be(false)
  end
end
