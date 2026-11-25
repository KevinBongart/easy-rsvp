# Shared setup for rate_limit in the public controllers that use it.
module RateLimitedPerClient
  # Production configures no cache_store and runs a single Puma process
  # (config/puma.rb sets no workers), so one in-memory store shared by its
  # threads sees every request; counters reset on deploy. The size cap evicts
  # old counters, so many addresses cannot exhaust memory.
  STORE = ActiveSupport::Cache::MemoryStore.new(size: 8.megabytes)

  private

  # Who counts as one client: the IP address, except that an IPv6 connection
  # usually gets a whole /64, so counting single addresses would let one
  # client rotate through millions of them.
  def rate_limit_client
    address = IPAddr.new(request.remote_ip)
    address.ipv6? && !address.ipv4_mapped? ? address.mask(64).to_s : address.to_s
  rescue IPAddr::Error
    request.remote_ip.to_s
  end

  # The neutral 429 page, saying what is limited with the controller's
  # LIMITED_MESSAGE.
  def render_rate_limited
    render "application/rate_limited", locals: { message: self.class::LIMITED_MESSAGE }, status: :too_many_requests,
      formats: :html, content_type: "text/html"
  end
end
