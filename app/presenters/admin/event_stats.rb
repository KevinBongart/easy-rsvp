# frozen_string_literal: true

require "action_view"
require "action_view/helpers"

module Admin
  class EventStats
    include ActionView::Helpers::NumberHelper

    DEFAULT_MONTHS_BACK = 6

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

    # Example: {2022=>"12", 2023=>"44"}
    def yearly_counts
      years = events.group_by { |e| e.created_at.year }
      years.sort.reverse.map { |year, evts| [year, number_with_delimiter(evts.size)] }.to_h
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
      current_month_start = (now).beginning_of_month
      days_in_month = current_month_start.end_of_month.day.to_f
      days_so_far = now.day.to_f

      return current_month_count if days_so_far.zero?

      extrapolated = (monthly_counts.first.last.to_f / days_so_far * days_in_month).round
      number_with_delimiter(extrapolated)
    end

    private

    def monthly_counts
      @monthly_counts ||= (0..months_back).map do |offset|
        month = (now - offset.months).beginning_of_month
        count = events.count { |event| event.created_at >= month && event.created_at < month + 1.month }
        [month, count]
      end
    end
  end
end
