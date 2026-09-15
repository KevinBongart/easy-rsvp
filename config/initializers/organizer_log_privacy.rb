require Rails.root.join('lib/organizer_token_redactor')

Rails.application.config.after_initialize do
  loggers = Rails.logger.respond_to?(:broadcasts) ? Rails.logger.broadcasts : [Rails.logger]
  loggers.each do |logger|
    logger.formatter = OrganizerTokenRedactor::Formatter.new(logger.formatter || Logger::Formatter.new)
  end
end

Honeybadger.configure do |config|
  config.before_notify do |notice|
    OrganizerTokenRedactor.scrub_honeybadger_notice(notice)
  end
end
