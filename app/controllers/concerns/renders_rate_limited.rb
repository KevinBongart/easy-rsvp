# Answers 429 with a short neutral message: JSON for JSON requests (the
# editor's uploads), a page otherwise. A concern rather than an
# ApplicationController method because the upload controller inherits from
# Active Storage's.
module RendersRateLimited
  private

  def render_rate_limited(message)
    if request.format.json?
      render json: { error: message }, status: :too_many_requests
    else
      render "application/rate_limited", locals: { message: }, status: :too_many_requests,
        formats: :html, content_type: "text/html"
    end
  end
end
