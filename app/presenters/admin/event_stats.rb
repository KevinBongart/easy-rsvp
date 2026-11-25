# frozen_string_literal: true

require "action_view"
require "action_view/helpers"

module Admin
  class EventStats
    include ActionView::Helpers::NumberHelper

    DEFAULT_MONTHS_BACK = 12

    attr_reader :events, :now, :months_back

    # events: ActiveRecord::Relation or Array of Event objects. Relations are
    # aggregated in SQL so rendering the dashboard never instantiates its history.
    # months_back: Integer, number of full months to show (default: DEFAULT_MONTHS_BACK)
    def initialize(events, now: Time.zone.now, months_back: DEFAULT_MONTHS_BACK)
      @events = events
      @now = now
      @months_back = months_back
    end

    # Example: "1,234"
    def total_events
      number_with_delimiter(summary.first)
    end

    def oldest_creation_date
      summary.last&.to_fs(:month_day_and_year)
    end

    def current_year_count
      number_with_delimiter(creation_counts_by_year.fetch(now.year, 0))
    end

    def extrapolated_current_year_count
      number_with_delimiter(yearly_chart.last[:projected_count])
    end

    # Example: [["April 2024", "5"], ["March 2024", "10"], ["February 2024", "12"], ["January 2024", "8"]]
    def monthly_counts_with_labels
      monthly_counts.map { |month, count| [ month.to_fs(:month_and_year), number_with_delimiter(count) ] }
    end

    # Example: "April 2024"
    def current_month_label
      monthly_counts_with_labels[0][0]
    end

    # Example: "5"
    def current_month_count
      monthly_counts_with_labels[0][1]
    end

    # Example: "15"
    def extrapolated_current_month_count
      number_with_delimiter(monthly_projection)
    end

    def yearly_chart
      return @yearly_chart if @yearly_chart

      counts = creation_counts_by_year
      first_year = [ counts.keys.min || now.year, now.year - 1 ].min
      actual = (first_year..now.year).map do |year|
        label = year == now.year ? "#{year} through #{now.to_fs(:month_and_day)}" : year.to_s
        { label: label, count: counts.fetch(year, 0) }
      end
      projection = (actual.last[:count].to_f / now.yday * now.end_of_year.yday).round
      @yearly_chart = actual + [ { label: "#{now.year} through December 31", projected_count: projection } ]
    end

    def monthly_chart
      monthly_counts.reverse.map do |month, count|
        point = { label: month.to_fs(:month_and_year), count: count }
        point[:projected_count] = monthly_projection if month == now.beginning_of_month
        point
      end
    end

    # Running totals make the last observed day and the month-end forecast
    # comparable to the monthly count shown beside this chart.
    def current_month_chart
      daily_counts = creation_counts_by_day
      total = 0
      (1..now.end_of_month.day).map do |day|
        point = { label: now.change(day: day).to_fs(:month_and_day) }
        if day <= now.day
          total += daily_counts.fetch(day, 0)
          point[:count] = total
        else
          point[:projected_count] = (total.to_f / now.day * day).round
        end
        point
      end
    end

    private

    def summary
      @summary ||= if relation?
        events.reorder(nil).pick(Arel.sql("COUNT(*)"), Arel.sql("MIN(events.created_at)"))
      else
        [ events.size, events.filter_map { |event| event&.created_at }.min ]
      end
    end

    def creation_counts_by_year
      @creation_counts_by_year ||= if relation?
        events.reorder(nil).group(Arel.sql("EXTRACT(YEAR FROM events.created_at)::integer")).count
      else
        events.group_by { |event| event.created_at.year }.transform_values(&:size)
      end
    end

    def monthly_projection
      (monthly_counts.first.last.to_f / now.day * now.end_of_month.day).round
    end

    def monthly_counts
      return @monthly_counts if defined?(@monthly_counts)

      counts = creation_counts_by_month
      @monthly_counts ||= (0..months_back).map do |offset|
        month = (now - offset.months).beginning_of_month
        [ month, counts.fetch(month.to_date, 0) ]
      end
    end

    def creation_counts_by_month
      return @creation_counts_by_month if defined?(@creation_counts_by_month)

      @creation_counts_by_month = if relation?
        first_month = (now - months_back.months).beginning_of_month
        events.where(created_at: first_month...(now.beginning_of_month + 1.month))
          .reorder(nil)
          .group(Arel.sql("DATE_TRUNC('month', events.created_at)::date"))
          .count
      else
        events.group_by { |event| event.created_at.to_date.beginning_of_month }.transform_values(&:size)
      end
    end

    def creation_counts_by_day
      if relation?
        events.where(created_at: now.beginning_of_month...(now.beginning_of_month + 1.month))
          .reorder(nil)
          .group(Arel.sql("EXTRACT(DAY FROM events.created_at)::integer"))
          .count
      else
        events.select do |event|
          event.created_at >= now.beginning_of_month && event.created_at < now.beginning_of_month + 1.month
        end.group_by { |event| event.created_at.day }.transform_values(&:size)
      end
    end

    def relation?
      events.is_a?(ActiveRecord::Relation)
    end
  end
end
