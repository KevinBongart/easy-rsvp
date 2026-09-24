module EventsHelper
  def event_schedule(event)
    date = event.date.to_fs(:week_day_and_date)
    return date unless event.timed?

    starts_at = event.starts_at.in_time_zone(event.time_zone)
    ends_at = event.ends_at.in_time_zone(event.time_zone)
    abbreviations = [ starts_at.zone, ends_at.zone ].uniq.join("/")
    "#{date}, #{starts_at.to_fs(:event_time)}–#{ends_at.to_fs(:event_time)} (#{abbreviations})"
  end

  def time_zone_identifiers
    TZInfo::Timezone.all_identifiers
  end

  def schedule_time_error(event, attribute)
    return "Your event needs both a start and end time" if event.errors.added?(attribute, :blank)

    event.errors[attribute].to_sentence.presence
  end
end
