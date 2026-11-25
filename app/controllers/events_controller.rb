class EventsController < ApplicationController
  include RateLimitedPerClient

  CREATION_LIMITED_MESSAGE = "To prevent abuse on Easy RSVP, we're limiting how many events you can create in a short window. Please try again later.".freeze
  VIEWS_LIMITED_MESSAGE = "To prevent abuse on Easy RSVP, we're limiting how many event pages you can open in a short window. Please try again later.".freeze
  # Page views and calendar downloads per client, across all events, to slow
  # anyone trying the guessable hashids older events still answer to. A
  # guest opens the page before responding and again after, so a room
  # answering together on one address (the RSVP limit allows 200 responses in
  # 10 minutes; the busiest legitimate event took 182 on the 2026-11-20
  # production copy) needs about 400.
  VIEWS_LIMIT = 600
  VIEWS_WINDOW = 10.minutes

  rate_limit to: VIEWS_LIMIT, within: VIEWS_WINDOW, store: RateLimitedPerClient::STORE, by: :rate_limit_client, with: :render_rate_limited,
    only: [ :show, :calendar ]
  before_action :prevent_search_indexing, only: [ :show, :calendar ]
  before_action :set_event, only: [ :show, :calendar ]
  before_action :set_placeholders, only: [ :new ]

  def show
    @rsvp = @event.rsvps.new
    @rsvps = @event.rsvps.persisted.order(:created_at, :id)

    @user_rsvp_hashids = session[@event.hashid] || []
    @responded = @rsvps.any? { |rsvp| rsvp.hashid.in? @user_rsvp_hashids }
  end

  def new
    @event = Event.new
  end

  def create
    @event = Event.new(event_params)
    result = RecentEventCreation.limit(request.remote_ip) { @event.save && @event }

    if result == :limited
      set_placeholders
      flash.now[:alert] = CREATION_LIMITED_MESSAGE
      render :new, status: :too_many_requests
    elsif result
      ManagedEvents.remember(session, @event)
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
    link_id = event_link_id_from_param(params[:id])
    @event = Event.find_by_link_id!(link_id)
    unless admin_preview?
      return render_removed_event if removed_for_this_browser?(@event)
      return redirect_to root_path, alert: "This event is no longer viewable." unless @event.published?
    end

    # An older event's hashid link moves to its current link. Removed
    # events answer 410 directly, so indexed spam is not redirected first.
    redirect_to({ id: @event }, status: :moved_permanently) if link_id != @event.link_id
  end

  def render_rate_limited
    render "application/rate_limited", locals: { message: VIEWS_LIMITED_MESSAGE }, status: :too_many_requests,
      formats: :html, content_type: "text/html"
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
