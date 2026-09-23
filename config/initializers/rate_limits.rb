module RateLimits
  EVENT_CREATIONS = 10
  EVENT_CREATION_WINDOW = 1.hour
  EVENT_RSVP_CHANGES = 30
  EVENT_RSVP_WINDOW = 10.minutes
  ALL_RSVP_CHANGES = 300
  ALL_RSVP_WINDOW = 1.hour
  DIRECT_UPLOADS = 20
  DIRECT_UPLOAD_WINDOW = 10.minutes
  DASHBOARD_FAILURES = 5
  DASHBOARD_FAILURE_WINDOW = 10.minutes

  def self.store
    @store ||= Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  end
end
