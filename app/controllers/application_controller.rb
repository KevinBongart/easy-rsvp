class ApplicationController < ActionController::Base
  # Counters for rate_limit. Production configures no cache_store and runs a
  # single Puma process (config/puma.rb sets no workers), so one in-memory
  # store shared by its threads sees every request; counters reset on deploy.
  # The size cap evicts old counters, so many addresses cannot exhaust memory.
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 8.megabytes)
  # Who rate_limit counts as one client. An IPv6 connection usually gets a
  # whole /64, so counting single addresses would let one client rotate
  # through millions of them.
  RATE_LIMIT_CLIENT = lambda do
    address = IPAddr.new(request.remote_ip)
    address.ipv6? && !address.ipv4_mapped? ? address.mask(64).to_s : address.to_s
  rescue IPAddr::Error
    request.remote_ip.to_s
  end

  private

  # Guests get the removed page for every spam event; only the browser that
  # created or manages a confidently flagged event is spared.
  def removed_for_this_browser?(event)
    event.spam? && !shown_to_its_creator?(event)
  end

  # Its spammer is not told they were caught (see Event#confidently_spam?).
  # Less certain flags stay removed: that organizer sees a notice instead.
  # The cheap session check runs first, so guests never run the rules.
  def shown_to_its_creator?(event)
    ManagedEvents.include?(session, event) && event.confidently_spam?
  end

  def event_hashid_from_param(parameterized_id)
    parameterized_id.to_s.split("-", 2).first
  end

  # Event pages are shared by direct link and are not meant to be found
  # through search engines. Keeping them out of search results also removes
  # the incentive to publish SEO spam as events.
  def prevent_search_indexing
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    @prevent_search_indexing = true
  end

  # True when the site administrator, signed in through the dashboard, views
  # this event's pages.
  def admin_preview?
    return @admin_preview if defined?(@admin_preview)

    @admin_preview = @event.present? && AdminPreview.active?(session)
  end

  # 410 tells search engines the page is gone for good, so spam that was
  # already indexed drops out faster than it would after a 404 or redirect.
  def render_removed_event
    prevent_search_indexing
    render "events/removed", status: :gone, formats: :html, content_type: "text/html"
  end
end
