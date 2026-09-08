require 'rails_helper'

RSpec.describe 'Public events', type: :request do
  it 'renders the creation form and editor' do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<trix-editor', 'event[title]', 'event[date(1i)]')
  end

  it 'creates an event and redirects only its creator to the organizer URL' do
    expect do
      post events_path, params: { event: { title: 'Dinner', date: '2026-10-10', body: '<div>At home</div>' } }
    end.to change(Event, :count).by(1)
    event = Event.order(:id).last
    expect(event).to have_attributes(title: 'Dinner', date: Date.new(2026, 10, 10))
    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
  end

  it 're-renders an invalid form without creating an event' do
    expect { post events_path, params: { event: { title: '', date: '' } } }.not_to change(Event, :count)
    expect(response.body).to include('can&#39;t be blank', '<trix-editor')
  end

  it 'does not accept protected creation attributes' do
    post events_path, params: { event: { title: 'Dinner', date: '2026-10-10', admin_token: 'chosen', published: false, show_rsvp_names: false } }
    event = Event.order(:id).last
    expect(event.admin_token).not_to eq('chosen')
    expect(event).to have_attributes(published: true, show_rsvp_names: true)
  end

  it 'rejects an absent event parameter object' do
    post events_path, params: { title: 'Wrong namespace' }
    expect(response).to have_http_status(:bad_request)
  end

  it 'renders a published event without disclosing its organizer credential' do
    event = create(:event)
    get event_path(event)
    expect(response.body).to include(event.title)
    expect(response.body).not_to include(event.admin_token)
  end

  it 'resolves an old title slug after the title changes' do
    event = create(:event)
    old_path = event_path(event)
    event.update!(title: 'Renamed dinner')
    get old_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Renamed dinner')
  end

  it 'redirects unpublished events away from the public page' do
    event = create(:event, :unpublished)
    get event_path(event)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq('This event is no longer viewable.')
  end

  it 'returns 404 for an unknown event hashid' do
    get '/not-an-event'
    expect(response).to have_http_status(:not_found)
  end

  it 'sanitizes rich text and escapes titles and guest names' do
    event = create(:event, title: '<script>title_attack()</script>', body: '<strong>Safe text</strong><img src=x onerror=attack()>')
    create(:rsvp, event: event, name: '<script>guest_attack()</script>')
    get event_path(event)
    expect(response.body).to include('<strong>Safe text</strong>', '&lt;script&gt;')
    expect(response.body).not_to include('<script>title_attack', '<script>guest_attack', 'onerror=')
  end

  it 'hides other guest names while retaining response totals' do
    event = create(:event, :private_names)
    create(:rsvp, event: event, name: 'Hidden guest')
    get event_path(event)
    expect(response.body).not_to include('Hidden guest')
    expect(response.body).to match(/Yes<\/strong>\s*\(1\)/)
  end
end
