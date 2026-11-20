require 'rails_helper'

RSpec.describe 'Admin sign-in failures', type: :request do
  let(:ip) { '203.0.113.7' }
  let(:limit) { AdminSignInFailures::LIMIT }

  def sign_in(password: 'spec-password', from: ip)
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials('spec-admin', password)
    get admin_events_path, headers: { 'HTTP_AUTHORIZATION' => credentials }, env: { 'REMOTE_ADDR' => from }
  end

  def fail_sign_ins(count, from: ip)
    count.times { sign_in(password: 'wrong', from:) }
  end

  it 'refuses every admin request, even with the right password, after too many failures' do
    fail_sign_ins(limit - 1)
    expect(response).to have_http_status(:unauthorized)
    sign_in
    expect(response).to have_http_status(:ok)

    fail_sign_ins(1)
    expect(response).to have_http_status(:unauthorized)
    sign_in
    expect(response).to have_http_status(:too_many_requests)
    expect(Nokogiri::HTML(response.body).at_css('main p').text).to eq(Admin::EventsController::SIGN_IN_LIMITED_MESSAGE)

    event = create(:event)
    post mark_spam_admin_event_path(event), headers: { 'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials('spec-admin', 'spec-password') },
      env: { 'REMOTE_ADDR' => ip }
    expect(response).to have_http_status(:too_many_requests)
    expect(event.reload.spam_at).to be_nil
  end

  it 'never counts successful sign-ins or requests without credentials' do
    (limit * 2).times { sign_in }
    (limit * 2).times { get admin_events_path, env: { 'REMOTE_ADDR' => ip } }
    expect(response).to have_http_status(:unauthorized)

    sign_in
    expect(response).to have_http_status(:ok)
  end

  it 'counts each client separately, treating an IPv6 /64 as one client' do
    fail_sign_ins(limit, from: '2001:db8:1:2::1')

    sign_in(from: '2001:db8:1:2:ffff::9')
    expect(response).to have_http_status(:too_many_requests)
    sign_in(from: '2001:db8:1:3::1')
    expect(response).to have_http_status(:ok)
    sign_in(from: '198.51.100.20')
    expect(response).to have_http_status(:ok)
  end

  it 'lets the client sign in again once the window has passed' do
    travel_to(Time.zone.local(2026, 11, 20, 12, 0)) { fail_sign_ins(limit) }

    travel_to(Time.zone.local(2026, 11, 20, 12, 59)) do
      sign_in
      expect(response).to have_http_status(:too_many_requests)
    end
    travel_to(Time.zone.local(2026, 11, 20, 13, 0, 1)) do
      sign_in
      expect(response).to have_http_status(:ok)
    end
  end

  it 'reports failures spread over many clients once, without refusing anyone' do
    alert = AdminSignInFailures::SITE_WIDE_ALERT
    allow(Honeybadger).to receive(:notify)

    (alert - 1).times { |n| sign_in(password: 'wrong', from: "198.51.100.#{n % 200 + 1}") }
    expect(Honeybadger).not_to have_received(:notify)

    2.times { sign_in(password: 'wrong', from: '192.0.2.1') }
    expect(Honeybadger).to have_received(:notify).once

    sign_in(from: '192.0.2.2')
    expect(response).to have_http_status(:ok)
  end

  it 'never accepts any credentials when the admin credentials are unset' do
    stub_const('ENV', ENV.to_h.merge('ADMIN_USER' => nil, 'ADMIN_PASSWORD' => nil))

    get admin_events_path, headers: { 'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials('', '') }

    expect(response).to have_http_status(:unauthorized)
  end
end
