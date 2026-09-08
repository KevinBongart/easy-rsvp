require 'rails_helper'

RSpec.describe 'Public RSVPs', type: :request do
  let(:event) { create(:event) }

  %w[Yes Maybe No].each do |answer|
    it "saves #{answer} and remembers ownership in the session" do
      expect do
        post event_rsvps_path(event), params: { rsvp: { name: 'Alex' }, commit: answer }
      end.to change { event.rsvps.count }.by(1)
      rsvp = event.rsvps.last
      expect(rsvp.response).to eq(answer.downcase)
      expect(request.session[event.hashid]).to include(rsvp.hashid)
      expect(response).to redirect_to(event)
    end
  end

  it 'rejects a blank name without saving or claiming ownership' do
    expect { post event_rsvps_path(event), params: { rsvp: { name: '' }, commit: 'Yes' } }.not_to change(Rsvp, :count)
    expect(flash[:alert]).to include('Please add your name')
    expect(request.session[event.hashid]).to be_nil
  end

  it 'does not let request attributes change the event or bypass the submit choice' do
    other = create(:event)
    post event_rsvps_path(event), params: { rsvp: { name: 'Alex', event_id: other.id, response: 'no' }, commit: 'Yes' }
    expect(Rsvp.order(:id).last).to have_attributes(event_id: event.id, response: 'yes')
  end

  it 'rejects an unsupported submit choice without saving' do
    expect { post event_rsvps_path(event), params: { rsvp: { name: 'Alex' }, commit: 'Unexpected' } }.not_to change(Rsvp, :count)
    expect(response).to redirect_to(event)
  end

  it 'handles a missing submit value without crashing' do
    post event_rsvps_path(event), params: { rsvp: { name: 'Alex' } }
    expect(response).to have_http_status(:bad_request)
    expect(event.rsvps).to be_empty
  end

  it 'allows deletion of a response owned by this session' do
    post event_rsvps_path(event), params: { rsvp: { name: 'Mine' }, commit: 'Yes' }
    own = event.rsvps.last
    expect { delete event_rsvp_path(event, own) }.to change(Rsvp, :count).by(-1)
    expect(response).to redirect_to(event)
  end

  it 'does not delete another response when the session owns a different one' do
    other = create(:rsvp, event: event)
    post event_rsvps_path(event), params: { rsvp: { name: 'Mine' }, commit: 'Yes' }
    expect { delete event_rsvp_path(event, other) }.not_to change(Rsvp, :count)
    expect(response).to redirect_to(event)
  end

  it 'denies deletion by a visitor with no ownership session without crashing' do
    rsvp = create(:rsvp, event: event)
    expect { delete event_rsvp_path(event, rsvp) }.not_to change(Rsvp, :count)
    expect(response).to redirect_to(event)
  end

  it 'removes a deleted response from the ownership session' do
    post event_rsvps_path(event), params: { rsvp: { name: 'Mine' }, commit: 'Yes' }
    own = event.rsvps.last
    delete event_rsvp_path(event, own)
    expect(request.session[event.hashid]).to be_nil
  end

  it 'rejects a response ID belonging to another event' do
    other = create(:rsvp)
    expect { delete event_rsvp_path(event, other) }.not_to change(Rsvp, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'shows this sessions own name when guest names are private' do
    event.update!(show_rsvp_names: false)
    create(:rsvp, event: event, name: 'Hidden guest')
    post event_rsvps_path(event), params: { rsvp: { name: 'My guest' }, commit: 'Yes' }
    follow_redirect!
    expect(response.body).to include('My guest')
    expect(response.body).not_to include('Hidden guest')
  end

  it 'keeps other owned responses and other event sessions when deleting one RSVP' do
    other_event = create(:event)
    post event_rsvps_path(other_event), params: { rsvp: { name: 'Elsewhere' }, commit: 'Yes' }
    elsewhere = other_event.rsvps.last
    post event_rsvps_path(event), params: { rsvp: { name: 'First' }, commit: 'Yes' }
    first = event.rsvps.last
    post event_rsvps_path(event), params: { rsvp: { name: 'Second' }, commit: 'Maybe' }
    second = event.rsvps.last

    delete event_rsvp_path(event, first)
    expect(request.session[event.hashid]).to eq([second.hashid])
    expect(request.session[other_event.hashid]).to eq([elsewhere.hashid])
    delete event_rsvp_path(event, second)
    expect(request.session[event.hashid]).to be_nil
    expect(request.session[other_event.hashid]).to eq([elsewhere.hashid])
  end

end
