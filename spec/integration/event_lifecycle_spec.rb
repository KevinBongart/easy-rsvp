require 'rails_helper'

RSpec.describe 'Independent organizer and guest sessions', type: :request do
  it 'keeps guest ownership and private names isolated across the full event lifecycle' do
    organizer = ActionDispatch::Integration::Session.new(Rails.application)
    first_guest = ActionDispatch::Integration::Session.new(Rails.application)
    second_guest = ActionDispatch::Integration::Session.new(Rails.application)
    organizer.post events_path, params: { event: { title: 'Private dinner', date: '2026-10-10' } }
    event = Event.order(:id).last
    organizer_url = event_admin_path(event, event.admin_token)
    organizer.patch organizer_url, params: { event: { show_rsvp_names: false } }

    first_guest.post event_rsvps_path(event), params: { rsvp: { name: 'First guest' }, commit: 'Yes' }
    second_guest.post event_rsvps_path(event), params: { rsvp: { name: 'Second guest' }, commit: 'Maybe' }
    first_guest.get event_path(event)
    expect(first_guest.response.body).to include('First guest')
    expect(first_guest.response.body).not_to include('Second guest', event.admin_token)
    second_guest.get event_path(event)
    expect(second_guest.response.body).to include('Second guest')
    expect(second_guest.response.body).not_to include('First guest', event.admin_token)

    organizer.get organizer_url
    expect(organizer.response.body).to include('First guest', 'Second guest')
    first_response = event.rsvps.find_by!(name: 'First guest')
    second_guest.delete event_rsvp_path(event, first_response)
    expect(Rsvp.exists?(first_response.id)).to be(true)
    first_guest.delete event_rsvp_path(event, first_response)
    expect(Rsvp.exists?(first_response.id)).to be(false)
    expect(event.rsvps.pluck(:name)).to eq(['Second guest'])
  end

  it 'requires a CSRF token for browser mutations when forgery protection is enabled' do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    expect { post events_path, params: { event: { title: 'Forged request', date: '2026-10-10' } } }.not_to change(Event, :count)
    expect(response).to have_http_status(422)
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
