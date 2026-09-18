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
    older_quiet = create(:event, title: 'Older quiet event')
    newer_quiet = create(:event, title: 'Newer quiet event')
    create_list(:rsvp, 3, event: popular)
    get admin_events_path, params: { sort: 'rsvps' }, headers: dashboard_headers
    doc = Nokogiri::HTML(response.body)
    rows = doc.css('tbody tr')
    expect(rows.map { |row| row.css('td')[0].text }).to eq([popular.title, newer_quiet.title, older_quiet.title])
    expect(rows.map { |row| row.css('td')[2].text }).to eq(%w[3 0 0])
  end

  it 'renders an empty state without broken statistics' do
    get admin_events_path, headers: dashboard_headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/Total events created:<\/strong>\s*0/)
  end

  it 'bounds queries and instantiated records as the database grows past one page' do
    insert_events(1001)
    create(:rsvp, event: Event.order(:id).last)
    get admin_events_path, headers: dashboard_headers # warm templates and schema

    first_page_queries = count_queries { get admin_events_path, headers: dashboard_headers }
    insert_events(1000)
    instantiated = Hash.new(0)
    subscriber = lambda do |*, payload|
      instantiated[payload[:class_name]] += payload[:record_count]
    end
    larger_database_queries = count_queries do
      ActiveSupport::Notifications.subscribed(subscriber, 'instantiation.active_record') do
        get admin_events_path, headers: dashboard_headers
      end
    end

    expect(larger_database_queries).to eq(first_page_queries)
    expect(larger_database_queries).to be <= 6
    expect(instantiated['Event']).to eq(Admin::EventsController::EVENTS_PER_PAGE)
    expect(instantiated['Rsvp']).to eq(0)
  end

  it 'shows creation counts even when all parties are scheduled in another month' do
    travel_to Time.zone.local(2026, 9, 10, 12)
    create_list(:event, 2, date: Date.new(2026, 11, 5), created_at: Time.zone.local(2026, 9, 2))
    create(:event, date: Date.new(2026, 9, 20), created_at: Time.zone.local(2026, 8, 2))
    get admin_events_path, headers: dashboard_headers
    text = Nokogiri::HTML(response.body).text.squish
    expect(text).to include('Total events created since August 2, 2026: 3', 'August 2026: 1')
    expect(text).to include('September 2026: 2 so far, 6 extrapolated')
    expect(text).to include('September 2026: 2 so far; 6 extrapolated')
  end

  it 'renders three compact charts with actual values and distinct forecasts' do
    travel_to Time.zone.local(2026, 9, 10, 12) do
      create(:event, created_at: Time.zone.local(2025, 1, 1))
      create_list(:event, 2, created_at: Time.zone.local(2026, 9, 1))
      get admin_events_path, headers: dashboard_headers
      doc = Nokogiri::HTML(response.body)
      expect(doc.css('.admin-sparkline svg[height="20"]').size).to eq(3)
      expect(doc.css('.admin-sparkline .sparkline-projection').size).to eq(3)
      expect(doc.css('.admin-sparkline polyline.sparkline-actual').size).to eq(3)
      expect(doc.css('#monthly-chart button').last['aria-label']).to eq('September 2026: 2 so far; 6 extrapolated')
      expect(doc.css('#current-month-chart button').last['aria-label']).to eq('September 30: 6 extrapolated')
      expect(doc.css('#yearly-chart button').first['aria-label']).to eq('2025: 1')
      expect(doc.css('#yearly-chart button')[-2]['aria-label']).to eq('2026 through September 10: 2')
      expect(doc.css('#yearly-chart button').last['aria-label']).to eq('2026 through December 31: 3 extrapolated')
      actual_points = doc.at_css('#yearly-chart polyline.sparkline-actual')['points'].split
      forecast_points = doc.at_css('#yearly-chart polyline.sparkline-projection')['points'].split
      expect(actual_points.size).to eq(2)
      expect(forecast_points.size).to eq(2)
      expect(forecast_points.first).to eq(actual_points.last)
      expect(forecast_points.last).not_to eq(actual_points.last)
      expect(doc.css('.admin-statistics').text).not_to match(/NaN|Infinity/)
    end
  end

  def insert_events(count)
    now = Time.current
    rows = Array.new(count) do
      {
        admin_token: SecureRandom.uuid,
        created_at: now,
        date: Date.current + 7.days,
        published: true,
        show_rsvp_names: true,
        title: "Scale event #{SecureRandom.hex(8)}",
        updated_at: now
      }
    end
    Event.insert_all!(rows)
  end

end
