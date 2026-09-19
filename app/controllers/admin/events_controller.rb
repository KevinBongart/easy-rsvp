module Admin
  class EventsController < ApplicationController
    http_basic_authenticate_with name: ENV["ADMIN_USER"], password: ENV["ADMIN_PASSWORD"]

    EVENTS_PER_PAGE = 1000
    RSVP_COUNT_SQL = <<~SQL.squish.freeze
      (SELECT COUNT(*) FROM rsvps WHERE rsvps.event_id = events.id)
    SQL
    HAS_ATTACHMENTS_SQL = <<~SQL.squish.freeze
      EXISTS (
        SELECT 1
        FROM action_text_rich_texts
        LEFT JOIN active_storage_attachments
          ON active_storage_attachments.record_type = 'ActionText::RichText'
          AND active_storage_attachments.record_id = action_text_rich_texts.id
          AND active_storage_attachments.name = 'embeds'
        WHERE action_text_rich_texts.record_type = 'Event'
          AND action_text_rich_texts.record_id = events.id
          AND action_text_rich_texts.name = 'body'
          AND (
            active_storage_attachments.id IS NOT NULL
            /* The Action Text migration preserved Trix's legacy attachment HTML. */
            OR action_text_rich_texts.body LIKE '%data-trix-attachment=%'
          )
      )
    SQL

    def index
      @event_stats = Admin::EventStats.new(Event.all)
      @events = listed_events.page(params[:page]).per(EVENTS_PER_PAGE)
    end

    private

    def listed_events
      events = Event.select(
        "events.*",
        "#{RSVP_COUNT_SQL} AS rsvps_count",
        "#{HAS_ATTACHMENTS_SQL} AS has_attachments"
      )
      events = events.where(Arel.sql(HAS_ATTACHMENTS_SQL)) if params[:attachments] == "1"

      if params[:sort] == "rsvps"
        events.order(Arel.sql("rsvps_count DESC"), id: :desc)
      else
        events.order(id: :desc)
      end
    end
  end
end
