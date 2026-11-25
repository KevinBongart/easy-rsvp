require 'rails_helper'

RSpec.describe 'Error report privacy', type: :request do
  let(:event) { create(:event) }
  let(:description) { '<div>Unmistakable description marker</div>' }
  let(:guest_name) { 'Zelda Quintessa' }
  let(:log_path) { Rails.root.join('log/test.log') }

  # Honeybadger does not report from the test environment, so the examples
  # route its notices to its in-memory test backend instead.
  around do |example|
    config = Honeybadger.config
    original_api_key, original_backend, original_sync = config[:api_key], config[:backend], config[:sync]
    config.set(:api_key, 'spec-api-key')
    config.set(:sync, true)
    config.backend = 'test'
    Honeybadger::Backend::Test.notifications.clear
    example.run
  ensure
    config.set(:api_key, original_api_key)
    config.set(:sync, original_sync)
    config.backend = original_backend
    Honeybadger::Backend::Test.notifications.clear
  end

  def reported_notice
    notices = Honeybadger::Backend::Test.notifications[:notices]
    expect(notices.size).to eq(1)
    notices.first.as_json
  end

  def logged_during
    start = File.size(log_path)
    yield
    File.binread(log_path, nil, start).force_encoding(Encoding::UTF_8)
  end

  it 'keeps the organizer token and description out of the notice, its breadcrumbs and the log' do
    token = event.admin_token
    allow_any_instance_of(OrganizerEventsController).to receive(:redirect_to).and_raise(RuntimeError, 'Synthetic failure')

    log = logged_during do
      expect do
        patch event_admin_path(event, token), params: { event: { body: description } }
      end.to raise_error(RuntimeError, 'Synthetic failure')
    end

    expect(event.reload.body.to_plain_text).to include('Unmistakable description marker')
    notice = reported_notice
    breadcrumb_paths = notice[:breadcrumbs][:trail].filter_map { |breadcrumb| breadcrumb[:metadata][:path] }
    expect(breadcrumb_paths).to include(a_string_including('/admin/[FILTERED]'))
    expect(notice[:request][:url]).to include('/admin/[FILTERED]')
    expect(log).to include('Started PATCH')
    [ JSON.generate(notice), log ].each do |output|
      expect(output.include?(token)).to be(false)
      expect(output.include?('Unmistakable description marker')).to be(false)
    end
  end

  it 'keeps the guest name out of the notice, its breadcrumbs and the log' do
    allow_any_instance_of(RsvpsController).to receive(:redirect_to).and_raise(RuntimeError, 'Synthetic failure')

    log = logged_during do
      expect do
        post event_rsvps_path(event), params: { rsvp: { name: guest_name }, commit: 'Yes' }
      end.to raise_error(RuntimeError, 'Synthetic failure')
    end

    expect(event.rsvps.sole.name).to eq(guest_name)
    notice = reported_notice
    expect(notice[:breadcrumbs][:trail]).not_to be_empty
    expect(notice[:request][:params]).to include('rsvp' => { 'name' => '[FILTERED]' })
    expect(notice[:request][:cgi_data]['SERVER_NAME']).to eq('www.example.com')
    expect(log).to include('INSERT INTO "rsvps"')
    [ JSON.generate(notice), log ].each do |output|
      expect(output.include?(guest_name)).to be(false)
      expect(output.include?(event.admin_token)).to be(false)
    end
  end
end
