require "rails_helper"

RSpec.describe "Core request performance", type: :request do
  REQUEST_BUDGET_MS = 50
  LARGE_ORGANIZER_REQUEST_BUDGET_MS = 100
  DATABASE_BUDGET_MS = 25
  SQL_BUDGET_MS = 25

  it "keeps the homepage within its query and response budgets" do
    get root_path

    metrics = measure_request { get root_path }

    expect(response).to have_http_status(:ok)
    expect_metrics(metrics, label: "homepage", max_queries: 0, max_allocations: 20_000, instances: {})
  end

  it "keeps event creation within its query and response budgets" do
    post events_path, params: event_attributes(title: "Warm creation")

    metrics = measure_request do
      post events_path, params: event_attributes(title: "Measured creation")
    end

    event = Event.order(:id).last
    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
    expect_metrics(metrics, label: "event creation", max_queries: 4, max_allocations: 20_000)
  end

  it "keeps public event rendering constant from zero to 100 RSVPs" do
    empty_event = create(:event)
    one_rsvp_event = create(:event)
    insert_rsvps(one_rsvp_event, 1)
    many_rsvps_event = create(:event)
    insert_rsvps(many_rsvps_event, 100)
    get event_path(many_rsvps_event)

    metrics = [ empty_event, one_rsvp_event, many_rsvps_event ].map do |event|
      measure_request { get event_path(event) }
    end

    expect(response).to have_http_status(:ok)
    expect(metrics.map(&:queries).uniq).to contain_exactly(metrics.first.queries)
    metrics.zip([ 0, 1, 100 ]).each do |measurement, count|
      expect_metrics(
        measurement,
        label: "public event with #{count} RSVPs",
        max_queries: 3,
        max_allocations: count == 100 ? 150_000 : nil,
        max_response_bytes: count == 100 ? 20.kilobytes : nil,
        instances: { "Event" => 1, "ActionText::RichText" => 1, "Rsvp" => count }
      )
    end
  end

  it "keeps organizer rendering constant from one to 100 RSVPs" do
    one_rsvp_event = create(:event)
    insert_rsvps(one_rsvp_event, 1)
    many_rsvps_event = create(:event)
    insert_rsvps(many_rsvps_event, 100)
    get event_admin_path(many_rsvps_event, many_rsvps_event.admin_token)

    metrics = [ one_rsvp_event, many_rsvps_event ].map do |event|
      measure_request { get event_admin_path(event, event.admin_token) }
    end

    expect(response).to have_http_status(:ok)
    expect(metrics.map(&:queries).uniq).to contain_exactly(metrics.first.queries)
    metrics.zip([ 1, 100 ]).each do |measurement, count|
      expect_metrics(
        measurement,
        label: "organizer page with #{count} RSVPs",
        max_queries: 3,
        max_duration: count == 100 ? LARGE_ORGANIZER_REQUEST_BUDGET_MS : REQUEST_BUDGET_MS,
        max_allocations: count == 100 ? 500_000 : nil,
        max_response_bytes: count == 100 ? 250.kilobytes : nil,
        instances: { "Event" => 1, "ActionText::RichText" => 1, "Rsvp" => count }
      )
    end
  end

  it "keeps event editing within its query and response budgets" do
    event = create(:event)
    insert_rsvps(event, 100)
    warm_event = create(:event)
    get edit_event_admin_path(event, event.admin_token)
    patch event_admin_path(warm_event, warm_event.admin_token), params: event_attributes(title: "Warm update")

    show_metrics = measure_request { get edit_event_admin_path(event, event.admin_token) }
    update_metrics = measure_request do
      patch event_admin_path(event, event.admin_token), params: event_attributes(title: "Updated event")
    end

    event.reload
    expect(response).to redirect_to(event_admin_path(event, event.admin_token))
    expect_metrics(
      show_metrics,
      label: "event edit form with 100 stored RSVPs",
      max_queries: 2,
      instances: { "Event" => 1, "ActionText::RichText" => 1 }
    )
    expect_metrics(
      update_metrics,
      label: "event update",
      max_queries: 3,
      max_allocations: 20_000,
      instances: { "Event" => 1, "ActionText::RichText" => 1 }
    )
  end

  it "keeps RSVP creation constant with zero or 100 existing RSVPs" do
    empty_event = create(:event)
    many_rsvps_event = create(:event)
    insert_rsvps(many_rsvps_event, 100)
    warm_event = create(:event)
    submit_rsvp(warm_event, "Warm guest")

    metrics = [ empty_event, many_rsvps_event ].map.with_index do |event, index|
      measure_request { submit_rsvp(event, "Measured guest #{index}") }
    end

    expect(response).to redirect_to(event_path(many_rsvps_event))
    expect(metrics.map(&:queries).uniq).to contain_exactly(metrics.first.queries)
    metrics.zip([ 0, 100 ]).each do |measurement, existing_count|
      expect_metrics(
        measurement,
        label: "RSVP creation with #{existing_count} existing RSVPs",
        max_queries: 2,
        max_allocations: 20_000,
        instances: { "Event" => 1 }
      )
    end
  end

  def event_attributes(title:)
    {
      event: {
        title: title,
        date: Date.new(2026, 10, 10),
        body: "<div>Bring something to share.</div>"
      }
    }
  end

  def insert_rsvps(event, count)
    now = Time.current
    rows = Array.new(count) do |index|
      {
        created_at: now + index.seconds,
        event_id: event.id,
        name: "Guest #{index}",
        response: Rsvp::RESPONSES.fetch(index % Rsvp::RESPONSES.size),
        updated_at: now + index.seconds
      }
    end
    Rsvp.insert_all!(rows) if rows.any?
  end

  def submit_rsvp(event, name)
    post event_rsvps_path(event), params: { rsvp: { name: name }, commit: "Yes" }
  end

  def expect_metrics(
    metrics,
    label:,
    max_queries:,
    max_duration: REQUEST_BUDGET_MS,
    instances: nil,
    max_allocations: nil,
    max_response_bytes: nil
  )
    summary = request_metrics_summary(metrics, label: label)

    aggregate_failures(label) do
      expect(metrics.queries).to be <= max_queries, summary
      expect(metrics.duration).to be < max_duration, summary
      expect(metrics.db_runtime).to be < DATABASE_BUDGET_MS, summary
      expect(metrics.sql_runtime).to be < SQL_BUDGET_MS, summary
      expected_instances = instances&.reject { |_class_name, count| count.zero? }
      expect(metrics.instantiations).to eq(expected_instances), summary if instances
      expect(metrics.allocations).to be <= max_allocations, summary if max_allocations
      expect(metrics.response_bytes).to be <= max_response_bytes, summary if max_response_bytes
    end
  end
end
