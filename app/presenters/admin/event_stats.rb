# frozen_string_literal: true

require "action_view"
require "action_view/helpers"

module Admin
  class EventStats
    include ActionView::Helpers::NumberHelper

    DEFAULT_MONTHS_BACK = 12

    attr_reader :events, :now, :months_back

    # events: ActiveRecord::Relation or Array of Event objects
    # months_back: Integer, number of full months to show (default: DEFAULT_MONTHS_BACK)
    def initialize(events, now: Time.zone.now, months_back: DEFAULT_MONTHS_BACK)
      @events = events
      @now = now
      @months_back = months_back
    end

    # Example: "1,234"
    def total_events
      number_with_delimiter(events.size)
    end

    def oldest_creation_date
      events.map(&:created_at).min&.strftime('%B %-d, %Y')
    end

    def current_year_count
      number_with_delimiter(creation_counts_by_year.fetch(now.year, 0))
    end

    def extrapolated_current_year_count
      number_with_delimiter(yearly_chart.last[:projected_count])
    end

    # Example: {2022=>"12", 2023=>"44"}
    def yearly_counts
      creation_counts_by_year.sort.reverse.map { |year, count| [year, number_with_delimiter(count)] }.to_h
    end

    # Example: "2022: 12, 2023: 44"
    def yearly_counts_display
      yearly_counts.map { |year, count| "#{year}: #{count}" }.join(", ")
    end

    # Example: [["April 2024", "5"], ["March 2024", "10"], ["February 2024", "12"], ["January 2024", "8"]]
    def monthly_counts_with_labels
      monthly_counts.map { |month, count| [month.strftime("%B %Y"), number_with_delimiter(count)] }
    end

    # Example: "March 2024: 10, February 2024: 12, January 2024: 8"
    def full_months_display
      # Skip current month (first element)
      monthly_counts_with_labels[1..months_back].map { |label, count| "#{label}: #{count}" }.join(", ")
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
      first_year = [counts.keys.min || now.year, now.year - 1].min
      actual = (first_year..now.year).map do |year|
        label = year == now.year ? "#{year} through #{now.strftime('%B %-d')}" : year.to_s
        { label: label, count: counts.fetch(year, 0) }
      end
      projection = (actual.last[:count].to_f / now.yday * now.end_of_year.yday).round
      @yearly_chart = actual + [{ label: "#{now.year} through December 31", projected_count: projection }]
    end

    def monthly_chart
      monthly_counts.reverse.map do |month, count|
        point = { label: month.strftime('%B %Y'), count: count }
        point[:projected_count] = monthly_projection if month == now.beginning_of_month
        point
      end
    end

    # Running totals make the last observed day and the month-end forecast
    # comparable to the monthly count shown beside this chart.
    def current_month_chart
      daily_counts = events.select do |event|
        event.created_at >= now.beginning_of_month && event.created_at < now.beginning_of_month + 1.month
      end.group_by { |event| event.created_at.day }.transform_values(&:size)
      total = 0
      (1..now.end_of_month.day).map do |day|
        point = { label: "#{now.strftime('%B')} #{day}" }
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

    def creation_counts_by_year
      @creation_counts_by_year ||= events.group_by { |event| event.created_at.year }.transform_values(&:size)
    end

    def monthly_projection
      (monthly_counts.first.last.to_f / now.day * now.end_of_month.day).round
    end

    def monthly_counts
      @monthly_counts ||= (0..months_back).map do |offset|
        month = (now - offset.months).beginning_of_month
        count = events.count { |event| event.created_at >= month && event.created_at < month + 1.month }
        [month, count]
      end
    end
  end
end
