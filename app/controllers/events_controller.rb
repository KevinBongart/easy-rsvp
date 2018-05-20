class EventsController < ApplicationController
  before_action :set_event, only: [:show]

  def show
    @rsvp = @event.rsvps.new
  end

  def new
    @event = Event.new
  end

  def create
    @event = Event.new(event_params)

    if @event.save
      redirect_to @event, notice: 'Event was successfully created.'
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
