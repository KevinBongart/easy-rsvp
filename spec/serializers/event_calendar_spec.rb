require 'rails_helper'

RSpec.describe EventCalendar do
  it 'uses a stable public identifier and escapes calendar text' do
    event = create(:event, title: 'Dinner, drinks', body: "Bring food;\nand friends")
    event_url = "https://example.com/#{event.to_param}"

    calendar = described_class.new(event, event_url: event_url).to_ical

    expect(calendar).to include("UID:#{event.hashid}@easy-rsvp.com")
    expect(calendar).to include('SUMMARY:Dinner\, drinks')
    expect(calendar).to include("DESCRIPTION:Bring food\\;\\nand friends")
    expect(calendar).to include("URL;VALUE=URI:#{event_url}")
  end

  it 'represents a date-only event as one non-inclusive all-day date range' do
    event = create(:event, date: Date.new(2026, 10, 10))

    calendar = Icalendar::Calendar.parse(described_class.new(event, event_url: 'https://example.com/event').to_ical).first
    calendar_event = calendar.events.first

    expect(calendar_event.dtstart.to_date).to eq(Date.new(2026, 10, 10))
    expect(calendar_event.dtend.to_date).to eq(Date.new(2026, 10, 11))
  end

  it 'includes the selected time zone and local start and end times' do
    event = create(:event, :timed, date: Date.new(2026, 10, 10))

    calendar = Icalendar::Calendar.parse(described_class.new(event, event_url: 'https://example.com/event').to_ical).first
    calendar_event = calendar.events.first

    expect(calendar.timezones.first.tzid.to_s).to eq('Europe/Paris')
    expect(calendar_event.dtstart.ical_params['tzid']).to eq([ 'Europe/Paris' ])
    expect(calendar_event.dtstart.strftime('%Y-%m-%d %H:%M')).to eq('2026-10-10 18:00')
    expect(calendar_event.dtend.strftime('%Y-%m-%d %H:%M')).to eq('2026-10-10 21:00')
  end
end
