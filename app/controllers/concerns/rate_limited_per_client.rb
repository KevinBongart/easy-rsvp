# Rails' rate_limit, counted per ClientDigest (IPv6 per /64) in
# ClientRequestCounts, answering 429 through RendersRateLimited.
module RateLimitedPerClient
  extend ActiveSupport::Concern
  include RendersRateLimited

  class_methods do
    def rate_limit_per_client(to:, within:, message:, **options)
      rate_limit(to:, within:, **options,
        by: -> { ClientDigest.for(request.remote_ip) },
        with: -> { render_rate_limited(message) },
        store: ClientRequestCounts::STORE)
    end
  end
end
