require 'rails_helper'

RSpec.describe 'Events marked as spam', type: :request do
  let(:event) { create(:event, :spam) }

  def expect_removed
    expect(response).to have_http_status(:gone)
    expect(response.headers['X-Robots-Tag']).to eq('noindex, nofollow')
  end

  it 'answers the public page with 410 Gone' do
    get event_path(event)

    expect_removed
    expect(response.body).to include('This event has been removed')
    expect(response.body).not_to include(event.title)
  end

  it 'answers the calendar download with 410 Gone' do
    get calendar_event_path(event)

    expect_removed
  end

  it 'answers unpublished spam with 410 Gone instead of a redirect' do
    event.update!(published: false)

    get event_path(event)

    expect_removed
  end

  it 'rejects new RSVPs' do
    expect {
      post event_rsvps_path(event), params: { rsvp: { name: 'Guest' }, commit: 'Yes' }
    }.not_to change(Rsvp, :count)

    expect_removed
  end

  it 'locks the organizer out of viewing, editing, and republishing' do
    get event_admin_path(event, event.admin_token)
    expect_removed

    patch event_admin_path(event, event.admin_token), params: { event: { title: 'Clean title' } }
    expect_removed

    post toggle_publish_event_admin_path(event, event.admin_token)
    expect_removed

    expect(event.reload).to have_attributes(spam_at: be_present, published: true)
    expect(event.title).not_to eq('Clean title')
  end

  it 'locks the organizer out of managing RSVPs' do
    rsvp = create(:rsvp, event: event)

    delete event_admin_rsvp_path(event, event.admin_token, rsvp)

    expect_removed
    expect(Rsvp.exists?(rsvp.id)).to be(true)
  end

  it 'leaves spam out of the admin dashboard' do
    legitimate = create(:event, title: 'Neighborhood potluck')
    create(:event, :spam, title: 'Peptides coupon code')

    get admin_events_path, headers: dashboard_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(legitimate.title)
    expect(response.body).not_to include('Peptides coupon code')
    expect(controller.view_assigns['event_stats'].total_events).to eq('1')
  end
end
