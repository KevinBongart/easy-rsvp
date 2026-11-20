module Admin
  class EventsController < ApplicationController
    include RendersRateLimited

    SIGN_IN_LIMITED_MESSAGE = "To prevent abuse on Easy RSVP, we're limiting sign-in attempts. Please try again later.".freeze

    before_action :authenticate_admin

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
      AdminPreview.start(session)
      @event_stats = Admin::EventStats.new(Event.not_spam)
      # Same monthly chart and projection, over spam only (one grouped query).
      @spam_stats = Admin::EventStats.new(Event.spam)
      @events = listed_events.page(params[:page]).per(EVENTS_PER_PAGE)
    end

    # Operator marks are final: guests and the organizer see the event as
    # removed, and later edits never clear them. update_columns skips the
    # save-time spam check on purpose. spam_decided_at makes the latest
    # decisions Event::SpamReview's examples.
    def mark_spam
      event = Event.find_by_hashid!(event_hashid_from_param(params[:id]))
      event.update_columns(spam_at: event.spam_at || Time.current, spam_source: "operator", spam_decided_at: Time.current)
      RecentEventCreation.record_spam!(event)
      redirect_after_spam_change admin_events_path, notice: "“#{event.title}” was marked as spam."
    end

    def unmark_spam
      event = Event.find_by_hashid!(event_hashid_from_param(params[:id]))
      event.update_columns(spam_at: nil, spam_source: "cleared", spam_decided_at: Time.current)
      RecentEventCreation.clear_spam!(event)
      redirect_after_spam_change admin_events_path(spam: "1"), notice: "“#{event.title}” is no longer marked as spam."
    end

    def close_session
      AdminPreview.stop(session)
      redirect_to root_path, notice: "Admin session closed."
    end

    private

    # HTTP Basic, like http_basic_authenticate_with, but counting failures
    # per client (AdminSignInFailures). A request without credentials only
    # asks the browser for them and does not count.
    def authenticate_admin
      failures = AdminSignInFailures.new(ClientDigest.for(request.remote_ip))
      return render_rate_limited(SIGN_IN_LIMITED_MESSAGE) if failures.too_many?

      authenticate_or_request_with_http_basic do |name, password|
        admin_credentials?(name, password).tap { |valid| failures.record unless valid }
      end
    end

    # Compares both values in full (& does not short-circuit), so timing
    # reveals neither which one was wrong nor its length. Unset credentials
    # never match, not even empty ones.
    def admin_credentials?(name, password)
      expected_name, expected_password = ENV["ADMIN_USER"].to_s, ENV["ADMIN_PASSWORD"].to_s
      return false if expected_name.empty? || expected_password.empty?

      ActiveSupport::SecurityUtils.secure_compare(name.to_s, expected_name) &
        ActiveSupport::SecurityUtils.secure_compare(password.to_s, expected_password)
    end

    # Buttons on preview pages pass return_to so the admin lands back on the
    # page they were viewing. url_from only accepts same-site URLs.
    def redirect_after_spam_change(fallback, notice:)
      if (target = url_from(params[:return_to]))
        redirect_to target, notice: notice
      else
        redirect_back_or_to fallback, notice: notice
      end
    end

    def listed_events
      events = (params[:spam] == "1" ? Event.spam : Event.not_spam).joins(Arel.sql(ATTACHMENT_STATS_JOIN_SQL)).select(
        "events.*",
        "#{RSVP_COUNT_SQL} AS rsvps_count",
        "COALESCE(attachment_stats.attachments_count, 0) AS attachments_count",
        "COALESCE(attachment_stats.attachments_size, 0) AS attachments_size"
      )
      events = events.where("COALESCE(attachment_stats.attachments_count, 0) > 0") if params[:attachments] == "1"
      events = events.where.not(starts_at: nil) if params[:timed] == "1"

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
