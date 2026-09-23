RSpec.configure do |config|
  config.before { RateLimits.store.clear }
end
