module Admin
  class EventsController < ApplicationController
    before_action :authenticate_dashboard

    EVENTS_PER_PAGE = 1000
    RSVP_COUNT_SQL = <<~SQL.squish.freeze
      (SELECT COUNT(*) FROM rsvps WHERE rsvps.event_id = events.id)
    SQL
    # Current Action Text uploads have relational blob metadata. The former
    # Trix uploader stored its attachment count and file sizes only in body HTML.
    ATTACHMENT_STATS_JOIN_SQL = <<~SQL.squish.freeze
      LEFT JOIN LATERAL (
        SELECT
          COALESCE(native_attachments.attachments_count, 0)
            + COALESCE(legacy_attachments.attachments_count, 0) AS attachments_count,
          COALESCE(native_attachments.attachments_size, 0)
            + COALESCE(legacy_attachments.attachments_size, 0) AS attachments_size
        FROM action_text_rich_texts
        LEFT JOIN LATERAL (
          SELECT
            COUNT(*) AS attachments_count,
            COALESCE(SUM(active_storage_blobs.byte_size), 0) AS attachments_size
          FROM active_storage_attachments
          INNER JOIN active_storage_blobs
            ON active_storage_blobs.id = active_storage_attachments.blob_id
          WHERE active_storage_attachments.record_type = 'ActionText::RichText'
            AND active_storage_attachments.record_id = action_text_rich_texts.id
            AND active_storage_attachments.name = 'embeds'
        ) native_attachments ON TRUE
        LEFT JOIN LATERAL (
          SELECT
            COUNT(*) AS attachments_count,
            COALESCE(SUM(unique_attachments.filesize), 0) AS attachments_size
          FROM (
            SELECT
              metadata->>'url' AS url,
              MAX(COALESCE((metadata->>'filesize')::bigint, 0)) AS filesize
            FROM (
              SELECT REPLACE((matches.value)[1], '&quot;', '"')::jsonb AS metadata
              FROM regexp_matches(
                action_text_rich_texts.body,
                'data-trix-attachment="([^"]+)"',
                'g'
              ) AS matches(value)
              UNION ALL
              SELECT REPLACE((matches.value)[1], '&quot;', '"')::jsonb AS metadata
              FROM regexp_matches(
                action_text_rich_texts.body,
                $$data-trix-attachment='([^']+)'$$,
                'g'
              ) AS matches(value)
            ) parsed_attachments
            WHERE metadata ? 'url'
            GROUP BY metadata->>'url'
          ) unique_attachments
        ) legacy_attachments ON TRUE
        WHERE action_text_rich_texts.record_type = 'Event'
          AND action_text_rich_texts.record_id = events.id
          AND action_text_rich_texts.name = 'body'
      ) attachment_stats ON TRUE
    SQL

    def index
      @event_stats = Admin::EventStats.new(Event.all)
      @events = listed_events.page(params[:page]).per(EVENTS_PER_PAGE)
    end

    private

    def authenticate_dashboard
      return rate_limit_response(RateLimits::DASHBOARD_FAILURE_WINDOW) if dashboard_authentication_blocked?

      if valid_dashboard_credentials?
        RateLimits.store.delete(dashboard_failure_key)
      else
        RateLimits.store.increment(
          dashboard_failure_key,
          1,
          expires_in: RateLimits::DASHBOARD_FAILURE_WINDOW
        )
        request_http_basic_authentication
      end
    end

    def dashboard_authentication_blocked?
      RateLimits.store.read(dashboard_failure_key).to_i >= RateLimits::DASHBOARD_FAILURES
    end

    def valid_dashboard_credentials?
      authenticate_with_http_basic do |username, password|
        ActiveSupport::SecurityUtils.secure_compare(username.to_s, ENV.fetch("ADMIN_USER")) &
          ActiveSupport::SecurityUtils.secure_compare(password.to_s, ENV.fetch("ADMIN_PASSWORD"))
      end
    end

    def dashboard_failure_key
      "dashboard-auth-failures:#{request.remote_ip}"
    end

    def listed_events
      events = Event.joins(Arel.sql(ATTACHMENT_STATS_JOIN_SQL)).select(
        "events.*",
        "#{RSVP_COUNT_SQL} AS rsvps_count",
        "COALESCE(attachment_stats.attachments_count, 0) AS attachments_count",
        "COALESCE(attachment_stats.attachments_size, 0) AS attachments_size"
      )
      events = events.where("COALESCE(attachment_stats.attachments_count, 0) > 0") if params[:attachments] == "1"

      case params[:sort]
      when "rsvps"
        events.order(Arel.sql("rsvps_count DESC"), id: :desc)
      when "attachments"
        events.order(Arel.sql("attachments_size DESC, attachments_count DESC"), id: :desc)
      else
        events.order(id: :desc)
      end
    end
  end
end
