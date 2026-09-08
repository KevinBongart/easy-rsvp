require 'rails_helper'

RSpec.describe 'Organizer events', type: :request do
  let(:event) { create(:event) }

  it 'shows the organizer page with its private and public links' do
    get event_admin_path(event, event.admin_token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(event.admin_token, 'id="public-link"')
  end

  it 'renders the edit form for the correct token' do
    get edit_event_admin_path(event, event.admin_token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('event[show_rsvp_names]', '<trix-editor')
  end

  it 'updates editable fields without rotating the credential' do
    token = event.admin_token
    patch event_admin_path(event, token), params: { event: { title: 'New title', body: '<div>Updated</div>', show_rsvp_names: false, admin_token: 'chosen' } }
    expect(event.reload).to have_attributes(title: 'New title', body: '<div>Updated</div>', show_rsvp_names: false, admin_token: token)
    expect(response).to redirect_to(event_admin_path(event, token))
  end

  it 'renders validation feedback and preserves the saved event on invalid update' do
    original = event.title
    patch event_admin_path(event, event.admin_token), params: { event: { title: '' } }
    expect(event.reload.title).to eq(original)
    expect(response.body).to include('can&#39;t be blank')
  end

  it 'can access an unpublished event with its organizer token' do
    event.update!(published: false)
    get event_admin_path(event, event.admin_token)
    expect(response).to have_http_status(:ok)
  end

  it 'toggles publication both ways' do
    2.times do
      before = event.reload.published?
      post toggle_publish_event_admin_path(event, event.admin_token)
      expect(event.reload.published?).to eq(!before)
      expect(response).to redirect_to(event_admin_path(event, event.admin_token))
    end
  end

  it 'deletes an empty event' do
    event
    expect { delete event_admin_path(event, event.admin_token) }.to change(Event, :count).by(-1)
    expect(response).to redirect_to(root_path)
  end

  [:get, :patch, :delete].each do |verb|
    it "rejects #{verb} with the wrong organizer token without mutation" do
      original = event.reload.attributes
      public_send(verb, event_admin_path(event, 'wrong'), params: { event: { title: 'Changed' } })
      expect(response).to have_http_status(:not_found)
      expect(event.reload.attributes).to eq(original)
    end
  end

  it 'rejects a token belonging to a different event' do
    other = create(:event)
    post toggle_publish_event_admin_path(event, other.admin_token)
    expect(response).to have_http_status(:not_found)
    expect(event.reload).to be_published
  end
end
