require "rails_helper"

RSpec.describe "Request rate limits", type: :request do
  let(:first_ip) { "192.0.2.10" }
  let(:second_ip) { "192.0.2.11" }

  it "limits event creation by IP without blocking another IP" do
    RateLimits::EVENT_CREATIONS.times { |index| create_event(index, first_ip) }

    expect do
      create_event("blocked", first_ip)
    end.not_to change(Event, :count)
    expect_rate_limited(RateLimits::EVENT_CREATION_WINDOW)

    expect do
      create_event("other IP", second_ip)
    end.to change(Event, :count).by(1)
  end

  it "shares an event-scoped limit across RSVP creation and deletion" do
    event = create(:event)
    RateLimits::EVENT_RSVP_CHANGES.times do |index|
      create_rsvp(event, "Guest #{index}", first_ip)
    end
    owned_rsvp = event.rsvps.first

    expect do
      delete event_rsvp_path(event, owned_rsvp), headers: remote_ip(first_ip)
    end.not_to change(Rsvp, :count)
    expect_rate_limited(RateLimits::EVENT_RSVP_WINDOW)

    other_event = create(:event)
    expect do
      create_rsvp(other_event, "Other event", first_ip)
    end.to change(Rsvp, :count).by(1)
    expect do
      create_rsvp(event, "Other IP", second_ip)
    end.to change(Rsvp, :count).by(1)
  end

  it "limits aggregate RSVP changes even when requests rotate across events" do
    events = create_list(:event, 11)
    RateLimits::ALL_RSVP_CHANGES.times do |index|
      attempt_invalid_rsvp(events.fetch(index % events.size), first_ip)
      expect(response).to redirect_to(events.fetch(index % events.size))
    end
    fresh_event = create(:event)
    allow(RateLimits.store).to receive(:increment).and_call_original

    post event_rsvps_path("never-seen"),
      params: { rsvp: { name: "Unknown event" }, commit: "Yes" },
      headers: remote_ip(first_ip)
    expect_rate_limited(RateLimits::ALL_RSVP_WINDOW)
    expect(RateLimits.store).to have_received(:increment).once

    expect do
      create_rsvp(fresh_event, "Blocked guest", first_ip)
    end.not_to change(Rsvp, :count)
    expect_rate_limited(RateLimits::ALL_RSVP_WINDOW)

    expect do
      create_rsvp(fresh_event, "Other IP", second_ip)
    end.to change(Rsvp, :count).by(1)
  end

  it "limits direct-upload authorization attempts before creating a blob" do
    RateLimits::DIRECT_UPLOADS.times do
      post rich_text_direct_uploads_path,
        params: { blob: upload_attributes.merge(content_type: "application/pdf") },
        headers: remote_ip(first_ip),
        as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    expect do
      post rich_text_direct_uploads_path,
        params: { blob: upload_attributes },
        headers: remote_ip(first_ip),
        as: :json
    end.not_to change(ActiveStorage::Blob, :count)
    expect_rate_limited(RateLimits::DIRECT_UPLOAD_WINDOW)

    expect do
      post rich_text_direct_uploads_path,
        params: { blob: upload_attributes },
        headers: remote_ip(second_ip),
        as: :json
    end.to change(ActiveStorage::Blob, :count).by(1)
  end

  it "limits only failed dashboard authentication and isolates IPs" do
    (RateLimits::DASHBOARD_FAILURES - 1).times { failed_dashboard_login(first_ip) }
    get admin_events_path, headers: dashboard_headers.merge(remote_ip(first_ip))
    expect(response).to have_http_status(:ok)

    RateLimits::DASHBOARD_FAILURES.times do
      failed_dashboard_login(first_ip)
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to be_present
    end

    get admin_events_path, headers: dashboard_headers.merge(remote_ip(first_ip))
    expect_rate_limited(RateLimits::DASHBOARD_FAILURE_WINDOW)

    get admin_events_path, headers: dashboard_headers.merge(remote_ip(second_ip))
    expect(response).to have_http_status(:ok)
  end

  def create_event(identifier, ip)
    post events_path,
      params: { event: { title: "Event #{identifier}", date: Date.current + 1.day } },
      headers: remote_ip(ip)
  end

  def create_rsvp(event, name, ip)
    post event_rsvps_path(event),
      params: { rsvp: { name: name }, commit: "Yes" },
      headers: remote_ip(ip)
  end

  def attempt_invalid_rsvp(event, ip)
    post event_rsvps_path(event),
      params: { rsvp: { name: "" }, commit: "Yes" },
      headers: remote_ip(ip)
  end

  def failed_dashboard_login(ip)
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials("spec-admin", "wrong")
    get admin_events_path, headers: { "HTTP_AUTHORIZATION" => credentials }.merge(remote_ip(ip))
  end

  def remote_ip(ip)
    { "REMOTE_ADDR" => ip }
  end

  def upload_attributes
    bytes = File.binread(Rails.root.join("spec/fixtures/files/party.png"))
    {
      filename: "party.png",
      content_type: "image/png",
      byte_size: bytes.bytesize,
      checksum: Digest::MD5.base64digest(bytes)
    }
  end

  def expect_rate_limited(window)
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq(window.to_i.to_s)
  end
end
