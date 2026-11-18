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

  # 410 tells search engines the page is gone for good, so spam that was
  # already indexed drops out faster than it would after a 404 or redirect.
  def render_removed_event
    prevent_search_indexing
    render "events/removed", status: :gone, formats: :html, content_type: "text/html"
  end
end
