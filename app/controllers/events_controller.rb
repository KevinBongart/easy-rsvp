class EventsController < ApplicationController
  before_action :set_event, only: [:show]
  before_action :set_placeholders, only: [:new]

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
      render :new
    end
  end

  private

  def set_event
    hashid = hashid_from_param(params[:id])
    @event = Event.find_by_hashid!(hashid)

    unless @event.published?
      redirect_to root_path, alert: 'This event is no longer viewable.'
    end
  end

  def set_placeholders
    @placeholders = {
      title: 'BBQ party in our backyard 🏡🍔🍻',
      body: "Hey everyone, summer is finally here so let's celebrate with some grilled food and cold beers! Our address: 1000 Hart Street in Brooklyn."
    }
  end

  def event_params
    params.require(:event).permit(:title, :date, :body)
  end

  def hashid_from_param(parameterized_id)
    parameterized_id.to_s.split('-').first
  end
end
