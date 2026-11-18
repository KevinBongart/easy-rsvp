class ApplicationController < ActionController::Base
  private

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

  # True when the site administrator opened this event's page through a signed
  # preview link from the admin dashboard.
  def admin_preview?
    return @admin_preview if defined?(@admin_preview)

    @admin_preview = @event.present? && AdminPreview.valid?(@event, params[AdminPreview::PARAM])
    # Keep the token out of Referer headers sent by this page's requests.
    # strict-origin sends only the origin; no-referrer would make browsers
    # send "Origin: null" on form posts, which fails Rails' CSRF origin check.
    response.set_header("Referrer-Policy", "strict-origin") if @admin_preview
    @admin_preview
  end

  # 410 tells search engines the page is gone for good, so spam that was
  # already indexed drops out faster than it would after a 404 or redirect.
  def render_removed_event
    prevent_search_indexing
    render "events/removed", status: :gone, formats: :html, content_type: "text/html"
  end
end
