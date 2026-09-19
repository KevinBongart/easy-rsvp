module Admin
  class EventsController < ApplicationController
    http_basic_authenticate_with name: ENV["ADMIN_USER"], password: ENV["ADMIN_PASSWORD"]

    EVENTS_PER_PAGE = 1000
    RSVP_COUNT_SQL = <<~SQL.squish.freeze
      (SELECT COUNT(*) FROM rsvps WHERE rsvps.event_id = events.id)
    SQL

    def index
      @event_stats = Admin::EventStats.new(Event.all)
      @events = listed_events.page(params[:page]).per(EVENTS_PER_PAGE)
    end

    private

    def listed_events
      events = Event.select("events.*", "#{RSVP_COUNT_SQL} AS rsvps_count")
      if params[:sort] == "rsvps"
        events.order(Arel.sql("rsvps_count DESC"), id: :desc)
      else
        events.order(id: :desc)
      end
    end
  end
end
