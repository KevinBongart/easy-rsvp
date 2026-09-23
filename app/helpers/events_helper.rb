module EventsHelper
  def event_schedule(event)
    date = event.date.to_fs(:week_day_and_date)
    return date unless event.timed?

    starts_at = event.starts_at.in_time_zone(event.time_zone)
    ends_at = event.ends_at.in_time_zone(event.time_zone)
    "#{date}, #{starts_at.to_fs(:event_time)}–#{ends_at.to_fs(:event_time)} (#{event.time_zone})"
  end

  def time_zone_identifiers
    TZInfo::Timezone.all_identifiers
  end
end
