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
end
