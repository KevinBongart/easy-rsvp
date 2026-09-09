require Rails.root.join('lib/organizer_token_redactor')

Rails.application.config.after_initialize do
  loggers = Rails.logger.respond_to?(:broadcasts) ? Rails.logger.broadcasts : [Rails.logger]
  loggers.each do |logger|
    logger.formatter = OrganizerTokenRedactor::Formatter.new(logger.formatter || Logger::Formatter.new)
  end
end

Rollbar.configure do |config|
  config.scrub_fields |= [:admin_token]
  config.transform << lambda do |payload|
    payload.replace(OrganizerTokenRedactor.scrub(payload))
  end
end
