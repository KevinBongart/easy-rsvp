require 'rails_helper'

# Public links use a link id, which encodes a random public number. Hashids,
# derived from sequential ids, keep working only for events created before
# link ids existed.
RSpec.describe 'Event links', type: :request do
  let(:legacy_event) { create(:event, title: 'Old garden party').tap { |event| event.update_column(:legacy_hashid, event.hashid) } }
  let(:new_event) { create(:event, title: 'New garden party') }

  context 'with an event created before link ids' do
    it 'redirects its hashid link permanently to its link id link' do
      get "/#{legacy_event.hashid}-old-garden-party"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(event_path(legacy_event))
      expect(event_path(legacy_event)).to eq("/#{legacy_event.link_id}-old-garden-party")
    end

    it 'redirects its hashid calendar link to its link id calendar link' do
      get "/#{legacy_event.hashid}/calendar.ics"

      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(calendar_event_path(legacy_event, format: :ics))
    end

    it 'answers 410 for a removed spam event without redirecting first' do
      legacy_event.update_columns(spam_at: Time.current, spam_source: 'operator')

      get "/#{legacy_event.hashid}"
      expect(response).to have_http_status(:gone)
    end

    it 'sends an unpublished event home without redirecting to its link id first' do
      legacy_event.update!(published: false)

      get "/#{legacy_event.hashid}-old-garden-party"
      expect(response).to redirect_to(root_path)
    end

    it 'still redirects for an admin previewing a removed spam event' do
      legacy_event.update_columns(spam_at: Time.current, spam_source: 'operator')
      get admin_events_path, headers: dashboard_headers

      get "/#{legacy_event.hashid}"
      expect(response).to redirect_to(event_path(legacy_event))
    end

    it 'accepts a response posted from a page loaded before the deploy, and keeps it deletable' do
      post "/#{legacy_event.hashid}-old-garden-party/rsvps", params: { rsvp: { name: 'Early guest' }, commit: 'Yes' }

      expect(response).to redirect_to(event_path(legacy_event))
      rsvp = legacy_event.rsvps.sole
      expect(session[legacy_event.hashid]).to eq([ rsvp.hashid ])

      follow_redirect!
      expect(Nokogiri::HTML(response.body).at_css(%(a[href="#{event_rsvp_path(legacy_event, rsvp)}"]))).to be_present
    end

    it 'keeps the organizer link working' do
      get "/#{legacy_event.hashid}-old-garden-party/admin/#{legacy_event.admin_token}"

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css('#public-link')['href']).to eq(event_path(legacy_event))
    end
  end

  context 'with an event the previous release created during the deploy' do
    let(:mid_deploy_event) do
      Event.insert({ title: 'Mid-deploy party', date: Date.current, admin_token: SecureRandom.uuid, created_at: Time.current, updated_at: Time.current })
      Event.find_by!(title: 'Mid-deploy party')
    end

    it 'redirects the hashid link its organizer was given, and keeps the organizer link working' do
      get "/#{mid_deploy_event.hashid}-mid-deploy-party"
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(event_path(mid_deploy_event))

      get "/#{mid_deploy_event.hashid}-mid-deploy-party/admin/#{mid_deploy_event.admin_token}"
      expect(response).to have_http_status(:ok)
    end
  end

  context 'with an event created since' do
    it 'serves its link id link' do
      get event_path(new_event)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('New garden party')
    end

    it 'does not answer to its guessable hashid or id' do
      [ "/#{new_event.hashid}", "/#{new_event.hashid}-new-garden-party", "/#{new_event.id}" ].each do |path|
        get path
        expect(response).to have_http_status(:not_found)
      end

      get "/#{new_event.hashid}/calendar.ics"
      expect(response).to have_http_status(:not_found)

      expect {
        post "/#{new_event.hashid}/rsvps", params: { rsvp: { name: 'Guesser' }, commit: 'Yes' }
      }.not_to change(Rsvp, :count)
      expect(response).to have_http_status(:not_found)

      get "/#{new_event.hashid}/admin/#{new_event.admin_token}"
      expect(response).to have_http_status(:not_found)
    end

    it 'needs the matching organizer token with its link id' do
      get event_admin_path(new_event, legacy_event.admin_token)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'rate limit' do
    let(:ip) { '203.0.113.7' }
    let(:limit) { EventsController::VIEWS_LIMIT }

    it 'counts page views, calendar downloads, and failed guesses per client, then refuses with a neutral 429 page' do
      (limit - 3).times { get event_path(new_event), env: { 'REMOTE_ADDR' => ip } }
      expect(response).to have_http_status(:ok)
      get "/#{new_event.hashid}", env: { 'REMOTE_ADDR' => ip }
      expect(response).to have_http_status(:not_found)
      get calendar_event_path(new_event, format: :ics), env: { 'REMOTE_ADDR' => ip }
      expect(response).to have_http_status(:ok)
      get "/#{legacy_event.hashid}", env: { 'REMOTE_ADDR' => ip }
      expect(response).to have_http_status(:moved_permanently)

      get event_path(new_event), env: { 'REMOTE_ADDR' => ip }
      expect(response).to have_http_status(:too_many_requests)
      expect(Nokogiri::HTML(response.body).at_css('main p').text).to eq(EventsController::VIEWS_LIMITED_MESSAGE)

      get event_path(new_event), env: { 'REMOTE_ADDR' => '198.51.100.20' }
      expect(response).to have_http_status(:ok)
    end
  end
end
