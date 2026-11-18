# frozen_string_literal: true

require "delegate"

module OrganizerTokenRedactor
  UUID = /\b[0-9a-f]{8}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{12}\b/i
  ORGANIZER_PATH = %r{(/[^/\s?\#]+/admin/)[^/\s?\#"<>]+}

  def self.redact(value)
    value.gsub(ORGANIZER_PATH, '\\1[FILTERED]').gsub(UUID, "[FILTERED]")
  end

  def self.scrub(value)
    case value
    when Hash then value.transform_values { |item| scrub(item) }
    when Array then value.map { |item| scrub(item) }
    when String then redact(value)
    else value
    end
  end

  HONEYBADGER_NOTICE_FIELDS = %i[
    error_message
    context
    cgi_data
    params
    session
    url
    local_variables
    details
  ].freeze

  def self.scrub_honeybadger_notice(notice)
    HONEYBADGER_NOTICE_FIELDS.each do |field|
      notice.public_send("#{field}=", scrub(notice.public_send(field)))
    end
  end

  class Formatter < SimpleDelegator
    def call(*arguments)
      OrganizerTokenRedactor.redact(__getobj__.call(*arguments))
    end
  end
end
