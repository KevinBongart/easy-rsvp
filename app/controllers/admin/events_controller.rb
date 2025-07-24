module Admin
  class EventsController < AdminController
    def index
      all_events = Event.all.includes(:rsvps).order(id: :desc).to_a
      all_events.sort_by! { |event| -event.rsvps.size } if params[:sort] == "rsvps"

      @event_stats = Admin::EventStats.new(all_events)
      @events = Kaminari.paginate_array(all_events).page(params[:page]).per(1000)
    end
  end
end
