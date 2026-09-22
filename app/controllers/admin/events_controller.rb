module Admin
  class EventsController < ApplicationController
    http_basic_authenticate_with name: ENV["ADMIN_USER"], password: ENV["ADMIN_PASSWORD"]

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
            (
              SELECT COUNT(*)
              FROM regexp_matches(action_text_rich_texts.body, 'data-trix-attachment=', 'g')
            ) AS attachments_count,
            (
              SELECT COALESCE(SUM((legacy_sizes.value)[1]::bigint), 0)
              FROM regexp_matches(
                action_text_rich_texts.body,
                '&quot;filesize&quot;[[:space:]]*:[[:space:]]*([0-9]+)',
                'g'
              ) AS legacy_sizes(value)
            ) AS attachments_size
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
