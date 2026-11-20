# Short-lived per-client request counters behind the controller rate limits
# (RateLimitedPerClient) and AdminSignInFailures. Keys hold ClientDigest
# digests, never addresses.
#
# The counters live in this Puma process's memory, shared by its threads, and
# reset on every deploy or restart, which is acceptable for windows of
# minutes to a day. Rails.cache is not used: production configures none (Rails
# would fall back to files under tmp/cache), and the test environment's null
# store would silently disable every limit. The size cap evicts the least
# recently used counters, so a flood of distinct addresses cannot exhaust
# memory.
module ClientRequestCounts
  STORE = ActiveSupport::Cache::MemoryStore.new(size: 8.megabytes)
end
