require 'rails_helper'

# Spam flagged with confidence (Event#confidently_spam?) looks like a normal
# event to the browser that created or manages it, so spammers reading the
# public code cannot tell they were caught. Guests still get 410 Gone.
RSpec.describe 'Confidently flagged spam', type: :request do
  let(:confident_title) { 'NextGen Peptides working coupon code: NEX55 – 25% Off' }

  def managed_hashids
    session[ManagedEvents::SESSION_KEY]
  end

  def create_event(title:)
    post events_path, params: { event: { title: title, date: '2026-12-24', body: '<div>Bring a dish</div>' } }
    Event.order(:id).last
  end

  def expect_no_spam_verdict
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('#spam-notice')).to be_nil
    expect(response.body).not_to match(/spam|advertising|promotional|can't see this event/i)
  end

  it 'shows the organizer pages like any other event' do
    event = create_event(title: confident_title)
    expect(event).to be_confidently_spam

    get event_admin_path(event, event.admin_token)
    expect_no_spam_verdict
    expect(response.headers['X-Robots-Tag']).to eq('noindex, nofollow')
    expect(Nokogiri::HTML(response.body).at_css('.organizer-actions .calendar-link')).to be_present

    get edit_event_admin_path(event, event.admin_token)
    expect_no_spam_verdict

    patch event_admin_path(event, event.admin_token), params: { event: { title: '' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Nokogiri::HTML(response.body).at_css('#spam-notice')).to be_nil
  end

  it 'serves the public page, calendar, and RSVPs to the creating browser only' do
    event = create_event(title: confident_title)

    get event_path(event)
    expect_no_spam_verdict
    expect(response.headers['X-Robots-Tag']).to eq('noindex, nofollow')
    expect(response.body).to include('NEX55')

    get calendar_event_path(event, format: :ics)
    expect(response).to have_http_status(:ok)

    expect {
      post event_rsvps_path(event), params: { rsvp: { name: 'Friend' }, commit: 'Yes' }
    }.to change(event.rsvps, :count).by(1)
    expect(response).to redirect_to(event_path(event))
    rsvp = event.rsvps.last
    delete event_rsvp_path(event, rsvp)
    expect(Rsvp.exists?(rsvp.id)).to be(false)

    reset! # a guest's browser
    get event_path(event)
    expect(response).to have_http_status(:gone)
    get calendar_event_path(event, format: :ics)
    expect(response).to have_http_status(:gone)
    expect {
      post event_rsvps_path(event), params: { rsvp: { name: 'Guest' }, commit: 'Yes' }
    }.not_to change(Rsvp, :count)
    expect(response).to have_http_status(:gone)
  end

  it 'counts a Jev score of at least 0.98 as confident' do
    event = create(:event, :flagged_as_spam)
    event.update_columns(spam_score: 0.98)

    get event_admin_path(event, event.admin_token)
    expect_no_spam_verdict

    get event_path(event)
    expect(response).to have_http_status(:ok)
  end

  it 'remembers events managed through a valid organizer link' do
    event = create(:event, :flagged_as_spam, title: confident_title)

    get event_admin_path(event, 'not-the-token')
    expect(response).to have_http_status(:not_found)
    get event_path(event)
    expect(response).to have_http_status(:gone)

    get edit_event_admin_path(event, event.admin_token)
    get event_path(event)
    expect(response).to have_http_status(:ok)
  end

  it 'keeps the verdict hidden after an edit leaves only one reason' do
    event = create_event(title: confident_title)

    patch event_admin_path(event, event.admin_token), params: { event: { title: 'NEX55 – 25% Off' } }
    expect(event.reload).to be_flagged_as_spam
    expect(Event::SpamCheck.reasons(title: event.title, html: '').size).to eq(1)

    get event_admin_path(event, event.admin_token)
    expect_no_spam_verdict
    get event_path(event)
    expect(response).to have_http_status(:ok)
  end

  it 'does not treat an operator previewing the organizer page as its creator' do
    event = create(:event, :flagged_as_spam, title: confident_title)
    get admin_events_path, headers: dashboard_headers

    get event_admin_path(event, event.admin_token)
    expect(response).to have_http_status(:ok)
    expect(managed_hashids).to be_nil

    delete close_session_admin_events_path, headers: dashboard_headers
    get event_path(event)
    expect(response).to have_http_status(:gone)
  end

  # Their organizer already sees the neutral notice, so the public page agrees
  # with it instead of contradicting it.
  it 'keeps less certain flags removed for everyone, the creator included' do
    event = create_event(title: 'Robux generator')
    expect(event).to be_flagged_as_spam
    expect(event).not_to be_confidently_spam

    get event_path(event)
    expect(response).to have_http_status(:gone)
    post event_rsvps_path(event), params: { rsvp: { name: 'Friend' }, commit: 'Yes' }
    expect(response).to have_http_status(:gone)
  end

  it 'keeps operator marks removed for the browser that created the event' do
    event = create_event(title: 'Garden party')
    event.update_columns(spam_at: Time.current, spam_source: 'operator', spam_score: 0.99)

    get event_path(event)
    expect(response).to have_http_status(:gone)
  end

  it 'remembers at most the 20 most recently managed events, without duplicates' do
    events = create_list(:event, 21)
    events.each { |event| get event_admin_path(event, event.admin_token) }
    expect(managed_hashids).to eq(events.last(20).map(&:hashid))

    get event_admin_path(events[1], events[1].admin_token)
    expect(managed_hashids).to eq(events.last(20).map(&:hashid).rotate(1))
  end
end
