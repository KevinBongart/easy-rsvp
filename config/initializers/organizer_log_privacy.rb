require Rails.root.join("lib/organizer_token_redactor")

Rails.application.config.after_initialize do
  loggers = Rails.logger.respond_to?(:broadcasts) ? Rails.logger.broadcasts : [ Rails.logger ]
  loggers.each do |logger|
    logger.formatter = OrganizerTokenRedactor::Formatter.new(logger.formatter || Logger::Formatter.new)
  end
end

Honeybadger.configure do |config|
  config.before_notify do |notice|
    OrganizerTokenRedactor.scrub_honeybadger_notice(notice)
  end
end

# Scout labels its traces with the request path, which it reads before this
# event fires. Replace it so organizer links never reach Scout.
ActiveSupport::Notifications.subscribe("start_processing.action_controller") do |event|
  ScoutApm::RequestManager.find&.annotate_request(uri: OrganizerTokenRedactor.redact(event.payload[:path]))
end
