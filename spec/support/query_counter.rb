module QueryCounter
  RequestMetrics = Data.define(
    :queries,
    :sql_runtime,
    :duration,
    :db_runtime,
    :view_runtime,
    :allocations,
    :instantiations,
    :response_bytes
  )

  def count_queries
    count = 0
    subscriber = lambda do |*, payload|
      count += 1 if application_query?(payload)
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { yield }
    count
  end

  def measure_request
    ActiveRecord::Base.connection.clear_query_cache
    queries = 0
    sql_runtime = 0.0
    instantiations = Hash.new(0)
    controller_event = nil
    sql_subscriber = lambda do |event|
      next unless application_query?(event.payload)

      queries += 1
      sql_runtime += event.duration
    end
    instantiation_subscriber = lambda do |event|
      payload = event.payload
      instantiations[payload[:class_name]] += payload[:record_count]
    end
    controller_subscriber = ->(event) { controller_event = event }

    ActiveSupport::Notifications.subscribed(sql_subscriber, 'sql.active_record') do
      ActiveSupport::Notifications.subscribed(instantiation_subscriber, 'instantiation.active_record') do
        ActiveSupport::Notifications.subscribed(controller_subscriber, 'process_action.action_controller') do
          yield
        end
      end
    end

    raise 'No controller action was instrumented' unless controller_event

    RequestMetrics.new(
      queries: queries,
      sql_runtime: sql_runtime,
      duration: controller_event.duration,
      db_runtime: controller_event.payload[:db_runtime].to_f,
      view_runtime: controller_event.payload[:view_runtime].to_f,
      allocations: controller_event.allocations,
      instantiations: instantiations.freeze,
      response_bytes: response.body.bytesize
    )
  end

  def request_metrics_summary(metrics, label:)
    "#{label}: queries=#{metrics.queries}, duration=#{metrics.duration.round(1)}ms, " \
      "db=#{metrics.db_runtime.round(1)}ms, sql=#{metrics.sql_runtime.round(1)}ms, " \
      "view=#{metrics.view_runtime.round(1)}ms, allocations=#{metrics.allocations}, " \
      "response=#{metrics.response_bytes}B, instantiations=#{metrics.instantiations.sort.to_h.inspect}"
  end

  private

  def application_query?(payload)
    !payload[:cached] && !payload[:name].in?(%w[SCHEMA TRANSACTION])
  end
end

RSpec.configure { |config| config.include QueryCounter }
