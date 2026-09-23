require 'rails_helper'

RSpec.describe 'Public events', type: :request do
  it 'renders the creation form and editor' do
    get root_path
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(response.body).to include('<trix-editor', 'event[title]', 'event[date(1i)]')
    expect(page.at_css('html')['lang']).to eq('en')
    expect(page.at_css('main')).to be_present
    expect(page.at_css('nav img#logo')['alt']).to eq('')
    expect(page.at_css('trix-editor[aria-label="More details (optional)"]')).to be_present
    expect(page.at_css('label.form-label.mb-2[for="event_body"]')).to be_present
    expect(page.at_css('fieldset legend').text).to eq('When is this happening?')
    expect(page.at_css('label[for="event_date_2i"]').text).to eq('Month')
    expect(page.at_css('label[for="event_date_3i"]').text).to eq('Day')
    expect(page.at_css('label[for="event_date_1i"]').text).to eq('Year')
    expect(page.at_css('label[for="event_timed"]').text).to include('Add a time')
    expect(page.at_css('input#event_time_zone')['list']).to eq('event-time-zones')
  end

  it 'loads the compiled asset entrypoints with Turbo tracking and integrity protection' do
    get root_path
    page = Nokogiri::HTML(response.body)

    stylesheet = page.at_css('link[rel="stylesheet"][href*="/assets/application-"][data-turbo-track="reload"]')
    expect(stylesheet).to be_present
    expect(stylesheet['integrity']).to start_with('sha256-')
    script = page.at_css('script[type="module"][src*="/assets/application-"][data-turbo-track="reload"]')
    expect(script).to be_present
    expect(script['integrity']).to start_with('sha256-')
  end

  it 'creates an event and redirects only its creator to the organizer URL' do
    expect do
      post events_path, params: { event: { title: 'Dinner', date: '2026-10-10', body: '<div>At home</div>' } }
    end.to change(Event, :count).by(1)
    event = Event.order(:id).last
    expect(event).to have_attributes(title: 'Dinner', date: Date.new(2026, 10, 10))
    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
  end

  it 'creates an event with required start and end times in its selected time zone' do
    expect do
      post events_path, params: {
        event: {
          title: 'Dinner',
          date: '2026-10-10',
          timed: '1',
          start_time: '18:00',
          end_time: '21:30',
          time_zone: 'Europe/Paris'
        }
      }
    end.to change(Event, :count).by(1)

    event = Event.order(:id).last
    expect(event).to have_attributes(
      starts_at: Time.utc(2026, 10, 10, 16, 0),
      ends_at: Time.utc(2026, 10, 10, 19, 30),
      time_zone: 'Europe/Paris'
    )
  end

  it 'rejects a timed event without an end time' do
    expect do
      post events_path, params: {
        event: {
          title: 'Dinner',
          date: '2026-10-10',
          timed: '1',
          start_time: '18:00',
          end_time: '',
          time_zone: 'Europe/Paris'
        }
      }
    end.not_to change(Event, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("End time can&#39;t be blank")
  end

  it 're-renders an invalid form without creating an event' do
    expect { post events_path, params: { event: { title: '', date: '' } } }.not_to change(Event, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Your event needs a name!', '<trix-editor')
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
    expect(response.body).to include(calendar_event_path(event, format: :ics))
    expect(response.body).not_to include(event.admin_token)
    expect(response.body).not_to include(event_admin_path(event, event.admin_token))
  end

  it 'renders a timed event in its selected time zone' do
    event = create(:event, :timed, date: Date.new(2026, 10, 10))

    get event_path(event)

    expect(response.body).to include('6:00 PM–9:00 PM (Europe/Paris)')
  end

  it 'does not add an organizer link to the public page in development' do
    event = create(:event)
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('development'))

    get event_path(event)

    expect(response.body).not_to include(event.admin_token)
    expect(response.body).not_to include(event_admin_path(event, event.admin_token))
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

  it 'downloads a date-only event as an all-day calendar entry' do
    event = create(:event, title: 'Dinner, drinks')

    get calendar_event_path(event, format: :ics)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/calendar')
    expect(response.headers['Content-Disposition']).to include('attachment', 'dinner-drinks.ics')
    calendar_event = Icalendar::Calendar.parse(response.body).first.events.first
    expect(calendar_event.summary.to_s).to eq('Dinner, drinks')
    expect(calendar_event.dtstart.to_date).to eq(event.date)
    expect(calendar_event.dtend.to_date).to eq(event.date + 1.day)
    expect(response.body).not_to include(event.admin_token)
  end

  it 'downloads a timed event with its selected time zone' do
    event = create(:event, :timed, date: Date.new(2026, 10, 10))

    get calendar_event_path(event, format: :ics)

    calendar = Icalendar::Calendar.parse(response.body).first
    calendar_event = calendar.events.first
    expect(calendar.timezones.first.tzid.to_s).to eq('Europe/Paris')
    expect(calendar_event.dtstart.ical_params['tzid']).to eq([ 'Europe/Paris' ])
    expect(calendar_event.dtstart.strftime('%Y-%m-%d %H:%M')).to eq('2026-10-10 18:00')
    expect(calendar_event.dtend.strftime('%Y-%m-%d %H:%M')).to eq('2026-10-10 21:00')
  end

  it 'uses the canonical public origin for a calendar link' do
    event = create(:event)
    allow(Rails.configuration.x).to receive(:public_origin).and_return('https://www.easy-rsvp.com')

    get calendar_event_path(event, format: :ics), headers: { 'HOST' => 'alternate.example' }

    calendar_event = Icalendar::Calendar.parse(response.body).first.events.first
    expect(calendar_event.url.to_s).to eq("https://www.easy-rsvp.com#{event_path(event)}")
    expect(calendar_event.uid.to_s).to eq("#{event.hashid}@easy-rsvp.com")
  end

  it 'does not expose a calendar download for an unpublished event' do
    event = create(:event, :unpublished)

    get calendar_event_path(event, format: :ics)

    expect(response).to redirect_to(root_path)
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
