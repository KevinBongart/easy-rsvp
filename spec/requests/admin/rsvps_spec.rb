require 'rails_helper'

RSpec.describe 'Organizer RSVP management', type: :request do
  let(:rsvp) { create(:rsvp) }
  let(:event) { rsvp.event }

  it 'updates a guests name and answer' do
    patch event_admin_rsvp_path(event, event.admin_token, rsvp), params: { rsvp: { name: 'Updated guest', response: 'maybe' } }
    expect(rsvp.reload).to have_attributes(name: 'Updated guest', response: 'maybe')
    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
  end

  it 'rejects blank fields and preserves the original response' do
    original = rsvp.attributes
    patch event_admin_rsvp_path(event, event.admin_token, rsvp), params: { rsvp: { name: '', response: '' } }
    expect(rsvp.reload.attributes).to eq(original)
    expect(flash[:alert]).to include('could not be updated')
  end

  it 'ignores reassignment to another event' do
    other = create(:event)
    patch event_admin_rsvp_path(event, event.admin_token, rsvp), params: { rsvp: { event_id: other.id, name: 'Updated' } }
    expect(rsvp.reload.event).to eq(event)
  end

  it 'deletes a response without needing the guests session' do
    rsvp
    expect { delete event_admin_rsvp_path(event, event.admin_token, rsvp) }.to change(Rsvp, :count).by(-1)
    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
  end

  [:patch, :delete].each do |verb|
    it "denies #{verb} using a token for another event" do
      other = create(:event)
      original = rsvp.attributes
      public_send(verb, event_admin_rsvp_path(event, other.admin_token, rsvp), params: { rsvp: { name: 'Changed' } })
      expect(response).to have_http_status(:not_found)
      expect(rsvp.reload.attributes).to eq(original)
    end

    it "denies cross-event #{verb} even with a valid organizer token" do
      other = create(:event)
      original = rsvp.attributes
      public_send(verb, event_admin_rsvp_path(other, other.admin_token, rsvp), params: { rsvp: { name: 'Changed' } })
      expect(response).to have_http_status(:not_found)
      expect(rsvp.reload.attributes).to eq(original)
    end
  end
end
