# frozen_string_literal: true

module Admin
  # Events created per UTC day, split into spam and legitimate, for the
  # dashboard's spam-wave chart. Admin::EventStats deliberately excludes spam;
  # this presenter counts every event so the two series can be compared.
  class DailyCreationCounts
    DEFAULT_DAYS = 90

    # Rails stores timestamps in UTC, so the date cast is the UTC day.
    DAY_SQL = "events.created_at::date"
    SPAM_COUNT_SQL = "COUNT(*) FILTER (WHERE events.spam_at IS NOT NULL)"
    LEGITIMATE_COUNT_SQL = "COUNT(*) FILTER (WHERE events.spam_at IS NULL)"

    attr_reader :days

    # events: ActiveRecord::Relation over every event, spam included.
    def initialize(events = Event.all, now: Time.current, days: DEFAULT_DAYS)
      @events = events
      @today = now.utc.to_date
      @days = days
    end

    def first_day = @today - (days - 1)

    def last_day = @today

    # Example: [{ date: Date, spam: 3, legitimate: 12 }, ...], oldest first,
    # one entry per day of the window including today.
    def series
      @series ||= begin
        counts = grouped_counts
        (first_day..last_day).map do |date|
          spam, legitimate = counts.fetch(date, [ 0, 0 ])
          { date: date, spam: spam, legitimate: legitimate }
        end
      end
    end

    def spam_total = series.sum { |day| day[:spam] }

    def legitimate_total = series.sum { |day| day[:legitimate] }

    def maximum = series.flat_map { |day| [ day[:spam], day[:legitimate] ] }.max || 0

    private

    # One grouped query; days without events are zero-filled by #series.
    def grouped_counts
      @events
        .where(created_at: first_day.in_time_zone("UTC")...(last_day + 1).in_time_zone("UTC"))
        .reorder(nil)
        .group(Arel.sql(DAY_SQL))
        .pluck(Arel.sql(DAY_SQL), Arel.sql(SPAM_COUNT_SQL), Arel.sql(LEGITIMATE_COUNT_SQL))
        .to_h { |date, spam, legitimate| [ date, [ spam, legitimate ] ] }
    end
  end
end
