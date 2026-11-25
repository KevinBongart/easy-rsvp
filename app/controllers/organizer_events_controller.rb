class OrganizerEventsController < ApplicationController
  include RateLimitedPerClient

  LIMITED_MESSAGE = "To prevent abuse on Easy RSVP, we're limiting how often an event can be changed in a short window. Please try again later.".freeze
  # Saves and publish toggles per client, across all events. Every text edit
  # queues a paid Jev review (EventSpamReviewJob), so this caps what one
  # address can spend. The burst limit is one save every 20 seconds for 10
  # minutes, well above an organizer fixing typos, even several organizers on
  # one shared address; the daily cap bounds a slow script to 100 reviews a
  # day instead of 4,320.
  BURST_LIMIT = 30
  BURST_WINDOW = 10.minutes
  DAILY_LIMIT = 100
  DAILY_WINDOW = 1.day

  rate_limit to: BURST_LIMIT, within: BURST_WINDOW, name: "burst", only: %i[update toggle_publish],
    store: RateLimitedPerClient::STORE, by: :rate_limit_client, with: :render_rate_limited
  rate_limit to: DAILY_LIMIT, within: DAILY_WINDOW, name: "daily", only: %i[update toggle_publish],
    store: RateLimitedPerClient::STORE, by: :rate_limit_client, with: :render_rate_limited
  before_action :prevent_search_indexing
  before_action :set_event
  before_action :set_spam_verdict, only: %i[show edit update]

  def show
    remember_managed_event
    @rsvps = @event.rsvps.persisted.order(:created_at, :id)
  end

  def edit
    remember_managed_event
  end

  def update
    if @event.update(event_params)
      redirect_to event_admin_path(@event, @event.admin_token), notice: "Your event was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @event.destroy
    redirect_to root_path, notice: "Event was successfully destroyed."
  end

  def toggle_publish
    @event.toggle!(:published)
    redirect_to event_admin_path(@event, @event.admin_token), notice: "Your event is now #{@event.published? ? 'live' : 'unpublished'}."
  end

  private

  def set_event
    hashid = event_hashid_from_param(params[:event_id])
    id = Event.decode_id(hashid)

    @event = Event.find_by!(id: id, admin_token: params[:admin_token])
    # Admin previews are read-only: they never unlock edits or deletion.
    preview = request.get? && admin_preview?
    render_removed_event if @event.spam_locked? && !preview
  end

  # Read before an update changes the text, so a failed edit still shows the
  # saved event's state. Confident spam looks like any other event.
  def set_spam_verdict
    verdict_hidden = @event.confidently_spam?
    @spam_notice_shown = @event.flagged_as_spam? && !verdict_hidden
    @shown_as_spam = @event.spam? && !verdict_hidden
  end

  # An operator previewing the page is not its organizer; remembering it
  # would show them the spam as live once the preview ends.
  def remember_managed_event
    ManagedEvents.remember(session, @event) unless admin_preview?
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def event_params
    params.require(:event).permit(:title, :date, :body, :show_rsvp_names, :schedule_enabled, :start_time, :end_time, :time_zone)
  end
end
