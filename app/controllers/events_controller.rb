class EventsController < ApplicationController
  before_action :set_event, only: [:show]

  def show
    @rsvp = @event.rsvps.new

    @user_rsvp_hashids = session[@event.hashid] || []
    @responded = @event.rsvps.where.not(id: nil).any? { |rsvp| rsvp.hashid.in? @user_rsvp_hashids }
  end

  def new
    @event = Event.new
    @placeholders = {
      title: 'BBQ party in our backyard 🏡🍔🍻',
      body: "Hey everyone, summer is finally here so let's celebrate with some grilled food and cold beers! Our address: 1000 Hart Street in Brooklyn."
    }
  end

  def create
    @event = Event.new(event_params)

    if @event.save
      redirect_to event_admin_path(@event, @event.admin_token), notice: "Here's your event!"
    else
      render :new
    end
  end

  private

  def set_event
    hashid = hashid_from_param(params[:id])
    @event = Event.find_by_hashid!(hashid)
  end

  def event_params
    params.require(:event).permit(:title, :date, :body)
  end

  def hashid_from_param(parameterized_id)
    parameterized_id.to_s.split('-').first
  end
end
