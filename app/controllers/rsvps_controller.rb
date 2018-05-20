class RsvpsController < ApplicationController
  before_action :set_event

  def create
    response = Rsvp::RESPONSES.find { |r| r == params[:commit].downcase.to_sym }
    @rsvp = @event.rsvps.new(rsvp_params.merge(response: response))

    if @event.save
      redirect_to @event, notice: 'Thank you for responding!'
    else
      redirect_to @event, error: 'wasd'
    end
  end

  private

  def set_event
    hashid = hashid_from_param(params[:event_id])
    @event = Event.find_by_hashid!(hashid)
  end

  def rsvp_params
    params.require(:rsvp).permit(:name)
  end

  def hashid_from_param(parameterized_id)
    parameterized_id.to_s.split('-').first
  end
end
