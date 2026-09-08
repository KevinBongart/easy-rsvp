class RsvpsController < ApplicationController
  before_action :set_event

  def create
    return head :bad_request unless params[:commit].is_a?(String)

    response = Rsvp::RESPONSES.find { |r| r == params[:commit].downcase.to_sym }
    @rsvp = @event.rsvps.new(rsvp_params.merge(response: response))

    if @rsvp.save
      session[@event.hashid] ||= []
      session[@event.hashid] << @rsvp.hashid

      redirect_to @event, notice: 'Thank you for responding!'
    else
      redirect_to @event, alert: 'Please add your name to your RSVP'
    end
  end

  def destroy
    @rsvp = @event.rsvps.find(params[:id])

    event_session = Array(session[@event.hashid])

    if @rsvp.hashid.in?(event_session)
      @rsvp.destroy
      event_session -= [@rsvp.hashid]
    end

    redirect_to @event
  end

  private

  def set_event
    hashid = hashid_from_param(params[:event_id])
    @event = Event.find_by_hashid!(hashid)
  end

  def rsvp_params
    attributes = params.require(:rsvp)
    unless attributes.is_a?(ActionController::Parameters)
      raise ActionController::ParameterMissing, :rsvp
    end
    attributes.permit(:name)
  end

  def hashid_from_param(parameterized_id)
    parameterized_id.to_s.split('-').first
  end
end
