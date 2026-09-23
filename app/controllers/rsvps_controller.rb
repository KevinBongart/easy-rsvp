class RsvpsController < ApplicationController
  rate_limit to: RateLimits::ALL_RSVP_CHANGES,
    within: RateLimits::ALL_RSVP_WINDOW,
    store: RateLimits.store,
    name: "all-events",
    with: -> { rate_limit_response(RateLimits::ALL_RSVP_WINDOW) },
    only: [ :create, :destroy ]
  rate_limit to: RateLimits::EVENT_RSVP_CHANGES,
    within: RateLimits::EVENT_RSVP_WINDOW,
    by: :event_rate_limit_key,
    store: RateLimits.store,
    with: -> { rate_limit_response(RateLimits::EVENT_RSVP_WINDOW) },
    only: [ :create, :destroy ]

  before_action :set_event

  def create
    return head :bad_request unless params[:commit].is_a?(String)

    response = Rsvp::RESPONSES.find { |r| r == params[:commit].downcase.to_sym }
    @rsvp = @event.rsvps.new(rsvp_params.merge(response: response))

    if @rsvp.save
      session[@event.hashid] ||= []
      session[@event.hashid] << @rsvp.hashid

      redirect_to @event, notice: "Thank you for responding!"
    else
      redirect_to @event, alert: "Please add your name to your RSVP"
    end
  end

  def destroy
    @rsvp = @event.rsvps.find(params[:id])

    event_session = Array(session[@event.hashid])

    if @rsvp.hashid.in?(event_session) && @rsvp.destroy
      remaining = event_session - [ @rsvp.hashid ]
      if remaining.empty?
        session.delete(@event.hashid)
      else
        session[@event.hashid] = remaining
      end
    end

    redirect_to @event
  end

  private

  def event_rate_limit_key
    [ request.remote_ip, event_hashid_from_param(params[:event_id]) ].join(":")
  end

  def set_event
    hashid = event_hashid_from_param(params[:event_id])
    @event = Event.find_by_hashid!(hashid)
    raise ActiveRecord::RecordNotFound unless @event.published?
  end

  def rsvp_params
    attributes = params.require(:rsvp)
    unless attributes.is_a?(ActionController::Parameters)
      raise ActionController::ParameterMissing, :rsvp
    end
    attributes.permit(:name)
  end
end
