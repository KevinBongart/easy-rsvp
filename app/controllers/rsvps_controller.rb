class RsvpsController < ApplicationController
  include RateLimitedPerClient

  LIMITED_MESSAGE = "To prevent abuse on Easy RSVP, we're limiting how many responses you can send in a short window. Please try again later.".freeze
  # Responses and deletions per client, across all events. On the 2026-11-20
  # production copy the busiest legitimate event took 182 responses in 10
  # minutes (3 events passed 60, 6 passed 40). A room answering together on
  # venue, school, or office Wi-Fi shares one address, so the limit sits above
  # that whole crowd; one address still cannot flood events without bound.
  WRITE_LIMIT = 200
  WRITE_WINDOW = 10.minutes

  rate_limit to: WRITE_LIMIT, within: WRITE_WINDOW, store: RateLimitedPerClient::STORE, by: :rate_limit_client, with: :render_rate_limited,
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
    elsif @rsvp.errors.of_kind?(:name, :blank)
      redirect_to @event, alert: "Please add your name to your RSVP"
    else
      redirect_to @event, alert: @rsvp.errors.full_messages.to_sentence
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

  def render_rate_limited
    render "application/rate_limited", locals: { message: LIMITED_MESSAGE }, status: :too_many_requests,
      formats: :html, content_type: "text/html"
  end

  def set_event
    hashid = event_hashid_from_param(params[:event_id])
    @event = Event.find_by_hashid!(hashid)
    return render_removed_event if removed_for_this_browser?(@event)

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
