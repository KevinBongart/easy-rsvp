module RateLimitResponses
  extend ActiveSupport::Concern

  private

  def rate_limit_response(retry_after)
    response.set_header("Retry-After", retry_after.to_i.to_s)
    head :too_many_requests
  end
end
