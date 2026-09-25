class EventsController < ApplicationController
  before_action :set_event, only: [ :show, :calendar ]
  before_action :set_placeholders, only: [ :new ]

  def show
    @rsvp = @event.rsvps.new
    @rsvps = @event.rsvps.persisted.order(created_at: :asc)

    @user_rsvp_hashids = session[@event.hashid] || []
    @responded = @rsvps.any? { |rsvp| rsvp.hashid.in? @user_rsvp_hashids }
  end

  def new
    @event = Event.new
  end

  def create
    @event = Event.new(event_params)

    if @event.save
      redirect_to event_admin_path(@event, @event.admin_token)
    else
      set_placeholders
      render :new, status: :unprocessable_content
    end
  end

  def calendar
    send_data EventCalendar.new(@event, event_url: calendar_event_url).to_ical,
      filename: "#{@event.title.parameterize.presence || 'event'}.ics",
      type: "text/calendar; charset=utf-8",
      disposition: "attachment"
  end

  private

  def set_event
    hashid = event_hashid_from_param(params[:id])
    @event = Event.find_by_hashid!(hashid)

    unless @event.published?
      redirect_to root_path, alert: "This event is no longer viewable."
    end
  end

  def set_placeholders
    @placeholders = {
      title: "BBQ party in our backyard 🏡🍔🍻",
      body: "Hey everyone, summer is finally here so let's celebrate with some grilled food and cold beers! Our address: 1000 Hart Street in Brooklyn."
    }
  end

  def event_params
    params.require(:event).permit(:title, :date, :body, :schedule_enabled, :start_time, :end_time, :time_zone)
  end

  def calendar_event_url
    origin = Rails.configuration.x.public_origin
    return event_url(@event) unless origin

    "#{origin.delete_suffix('/')}#{event_path(@event)}"
  end
end
