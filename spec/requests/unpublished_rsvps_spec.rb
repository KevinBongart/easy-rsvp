require 'rails_helper'

RSpec.describe 'RSVP access while an event is unpublished', type: :request do
  let!(:event) { create(:event, :unpublished) }

  it 'blocks guest additions without saving a response or claiming ownership' do
    pending 'Assessment 1.5: guest additions ignore event publication'
    expect do
      post event_rsvps_path(event), params: { rsvp: { name: 'Guest' }, commit: 'Yes' }
    end.not_to change(Rsvp, :count)
    expect(response).to have_http_status(:not_found)
    expect(request.session[event.hashid]).to be_nil
  end

  it 'blocks deletion even when the guest owns a response from before unpublishing' do
    event.update!(published: true)
    post event_rsvps_path(event), params: { rsvp: { name: 'Existing guest' }, commit: 'Maybe' }
    rsvp = event.rsvps.last
    event.update!(published: false)

    pending 'Assessment 1.5: guest deletion ignores event publication'
    expect { delete event_rsvp_path(event, rsvp) }.not_to change(Rsvp, :count)
    expect(response).to have_http_status(:not_found)
    expect(request.session[event.hashid]).to include(rsvp.hashid)
  end

  it 'allows the organizer to edit the event while it is unpublished' do
    patch event_admin_path(event, event.admin_token), params: { event: { title: 'Updated private event' } }
    expect(event.reload).to have_attributes(title: 'Updated private event', published: false)
    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
  end

  it 'allows the organizer to update an existing response while unpublished' do
    rsvp = create(:rsvp, event: event)
    patch event_admin_rsvp_path(event, event.admin_token, rsvp), params: { rsvp: { name: 'Updated guest', response: 'no' } }
    expect(rsvp.reload).to have_attributes(name: 'Updated guest', response: 'no')
    expect(event.reload).not_to be_published
    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
  end

  it 'allows the organizer to delete an existing response while unpublished' do
    rsvp = create(:rsvp, event: event)
    expect do
      delete event_admin_rsvp_path(event, event.admin_token, rsvp)
    end.to change(Rsvp, :count).by(-1)
    expect(event.reload).not_to be_published
    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
  end

  it 'allows guest additions again after the organizer republishes the event' do
    post toggle_publish_event_admin_path(event, event.admin_token)
    expect(event.reload).to be_published
    expect do
      post event_rsvps_path(event), params: { rsvp: { name: 'Returning guest' }, commit: 'Yes' }
    end.to change(Rsvp, :count).by(1)
    expect(response).to redirect_to(event)
    expect(request.session[event.hashid]).to include(event.rsvps.last.hashid)
  end
end
