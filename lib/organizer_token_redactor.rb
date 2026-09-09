# frozen_string_literal: true

require 'delegate'

module OrganizerTokenRedactor
  UUID = /\b[0-9a-f]{8}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{12}\b/i
  ORGANIZER_PATH = %r{(/[^/\s?\#]+/admin/)[^/\s?\#"<>]+}

  def self.redact(value)
    value.gsub(ORGANIZER_PATH, '\\1[FILTERED]').gsub(UUID, '[FILTERED]')
  end

  # Rollbar payloads include URLs in request metadata, frames and messages.
  def self.scrub(value)
    case value
    when Hash then value.transform_values { |item| scrub(item) }
    when Array then value.map { |item| scrub(item) }
    when String then redact(value)
    else value
    end
  end

  class Formatter < SimpleDelegator
    def call(*arguments)
      OrganizerTokenRedactor.redact(__getobj__.call(*arguments))
    end
  end
end
