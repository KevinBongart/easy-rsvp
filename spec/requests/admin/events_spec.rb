require 'rails_helper'

RSpec.describe 'Site administrator dashboard', type: :request do
  it 'requires HTTP Basic authentication' do
    get admin_events_path
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an incorrect password' do
    get admin_events_path, headers: { 'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials('spec-admin', 'wrong') }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'lists events and their organizer links for an authenticated administrator' do
    event = create(:event)
    get admin_events_path, headers: dashboard_headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(event.title, event.admin_token)
  end

  it 'sorts events by RSVP count when requested' do
    popular = create(:event, title: 'Popular event')
    quiet = create(:event, title: 'Quiet event')
    create_list(:rsvp, 3, event: popular)
    get admin_events_path, params: { sort: 'rsvps' }, headers: dashboard_headers
    doc = Nokogiri::HTML(response.body)
    expect(doc.css('tbody tr td:nth-child(2)').map(&:text)).to eq([popular.title, quiet.title])
  end

  it 'renders an empty state without broken statistics' do
    get admin_events_path, headers: dashboard_headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/Total events created:<\/strong>\s*0/)
  end

  it 'does not introduce N+1 queries as the listing grows' do
    create(:rsvp)
    get admin_events_path, headers: dashboard_headers # warm templates and schema
    small = count_queries { get admin_events_path, headers: dashboard_headers }
    create_list(:rsvp, 10)
    large = count_queries { get admin_events_path, headers: dashboard_headers }
    expect(large).to eq(small)
    expect(large).to be <= 3
  end

  it 'shows creation counts even when all parties are scheduled in another month' do
    travel_to Time.zone.local(2026, 9, 10, 12)
    create_list(:event, 2, date: Date.new(2026, 11, 5), created_at: Time.zone.local(2026, 9, 2))
    create(:event, date: Date.new(2026, 9, 20), created_at: Time.zone.local(2026, 8, 2))
    get admin_events_path, headers: dashboard_headers
    text = Nokogiri::HTML(response.body).text.squish
    expect(text).to include('Total events created: 3', 'August 2026: 1')
    expect(text).to include('This month (September 2026) — events created: 2 so far, extrapolated: 6')
  end

end
