module Admin
  class EventsController < AdminController
    def index
      @events = Event.all.includes(:rsvps).order(created_at: :desc)
      @event_stats = Admin::EventStats.new(@events)
    end
  end
end
