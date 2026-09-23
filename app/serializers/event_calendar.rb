require "icalendar"

class EventCalendar
  def initialize(event, event_url:)
    @event = event
    @event_url = event_url
  end

  def to_ical
    calendar = Icalendar::Calendar.new
    calendar.prodid = "-//Easy RSVP//Event//EN"
    calendar.event { |calendar_event| populate(calendar_event) }
    calendar.publish
    calendar.to_ical
  end

  private

  attr_reader :event, :event_url

  def populate(calendar_event)
    calendar_event.uid = "#{event.hashid}@easy-rsvp.com"
    calendar_event.dtstamp = event.updated_at.utc
    calendar_event.last_modified = event.updated_at.utc
    calendar_event.summary = event.title
    calendar_event.description = event.body.to_plain_text.presence
    calendar_event.url = event_url

    if event.timed?
      calendar_event.dtstart = calendar_time(event.starts_at)
      calendar_event.dtend = calendar_time(event.ends_at)
    else
      calendar_event.dtstart = Icalendar::Values::Date.new(event.date)
      calendar_event.dtend = Icalendar::Values::Date.new(event.date + 1.day)
    end
  end

  def calendar_time(timestamp)
    Icalendar::Values::DateTime.new(timestamp.utc.to_datetime, "tzid" => "UTC")
  end
end
