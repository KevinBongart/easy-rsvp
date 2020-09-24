module Admin
  class EventsController < AdminController
    def index
      @events = Event.all.includes(:rsvps).order(created_at: :desc)
    end
  end
end
