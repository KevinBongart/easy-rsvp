require 'rails_helper'

RSpec.describe 'Organizer events', type: :request do
  let(:event) { create(:event) }

  it 'shows the organizer page with its private and public links' do
    get event_admin_path(event, event.admin_token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(event.admin_token, 'id="public-link"')
  end

  it 'renders Bootstrap 5 modal controls with unique form field IDs' do
    create_list(:rsvp, 2, event: event)

    get event_admin_path(event, event.admin_token)
    page = Nokogiri::HTML(response.body)

    expect(page.css('a[data-bs-toggle="modal"][data-bs-target^="#rsvp_"]').length).to eq(2)
    expect(page.css('button[data-bs-dismiss="modal"]').length).to eq(2)
    expect(page.css('[data-toggle], [data-target], [data-dismiss]')).to be_empty
    name_ids = page.css('.modal input[name="rsvp[name]"]').map { |input| input['id'] }
    expect(name_ids.uniq.length).to eq(2)
  end

  it 'renders the edit form for the correct token' do
    get edit_event_admin_path(event, event.admin_token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('event[show_rsvp_names]', '<trix-editor')
    expect(Nokogiri::HTML(response.body).at_css('label.form-label.mb-2[for="event_body"]')).to be_present
  end

  it 'updates editable fields without rotating the credential' do
    token = event.admin_token
    patch event_admin_path(event, token), params: { event: { title: 'New title', body: '<div>Updated</div>', show_rsvp_names: false, admin_token: 'chosen' } }
    event.reload
    expect(event).to have_attributes(title: 'New title', show_rsvp_names: false, admin_token: token)
    expect(event.body.to_plain_text).to eq('Updated')
    expect(response).to redirect_to(event_admin_path(event, token))
  end

  it 'renders validation feedback and preserves the saved event on invalid update' do
    original = event.title
    patch event_admin_path(event, event.admin_token), params: { event: { title: '' } }
    expect(event.reload.title).to eq(original)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Please tell us what you&#39;re planning.')
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

  it 'deletes an event and its responses without touching another events responses' do
    create_list(:rsvp, 2, event: event)
    other = create(:rsvp)
    expect do
      delete event_admin_path(event, event.admin_token)
    end.to change(Event, :count).by(-1).and change(Rsvp, :count).by(-2)
    expect(response).to redirect_to(root_path)
    expect(Rsvp.exists?(other.id)).to be(true)
  end

  it 'preserves responses when event deletion uses the wrong token' do
    rsvp = create(:rsvp, event: event)
    expect do
      delete event_admin_path(event, 'wrong')
    end.not_to change(Rsvp, :count)
    expect(response).to have_http_status(:not_found)
    expect(rsvp.reload.event).to eq(event)
  end

end
