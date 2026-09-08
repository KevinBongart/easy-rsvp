module QueryCounter
  def count_queries
    count = 0
    subscriber = lambda do |*, payload|
      count += 1 unless payload[:cached] || payload[:name].in?(%w[SCHEMA TRANSACTION])
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { yield }
    count
  end
end

RSpec.configure { |config| config.include QueryCounter }
