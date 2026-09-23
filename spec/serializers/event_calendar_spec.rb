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

  it 'represents timed events as exact UTC instants' do
    event = create(:event, :timed, date: Date.new(2026, 10, 10))

    serialized = described_class.new(event, event_url: 'https://example.com/event').to_ical
    calendar = Icalendar::Calendar.parse(serialized).first
    calendar_event = calendar.events.first

    expect(calendar.timezones).to be_empty
    expect(serialized).to include("DTSTART:20261010T160000Z")
    expect(serialized).to include("DTEND:20261010T190000Z")
    expect(calendar_event.dtstart.to_time).to eq(event.starts_at)
    expect(calendar_event.dtend.to_time).to eq(event.ends_at)
  end

  it 'keeps the correct instant around a daylight-saving transition' do
    zone = ActiveSupport::TimeZone['America/New_York']
    event = create(
      :event,
      date: Date.new(2026, 3, 8),
      starts_at: zone.local(2026, 3, 8, 3, 30),
      ends_at: zone.local(2026, 3, 8, 4, 30),
      time_zone: 'America/New_York'
    )

    serialized = described_class.new(event, event_url: 'https://example.com/event').to_ical

    expect(serialized).to include("DTSTART:20260308T073000Z")
    expect(serialized).to include("DTEND:20260308T083000Z")
    expect(serialized).not_to include('BEGIN:VTIMEZONE')
  end
end
