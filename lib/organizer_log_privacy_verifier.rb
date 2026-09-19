class OrganizerLogPrivacyVerifier
  SYNTHETIC_TOKEN = '11111111-2222-4333-8444-555555555555'
  FILTERED_PATH = '/[FILTERED]/admin/[FILTERED]'
  UNSAFE_VARIABLES = %w[$request $request_uri $args].freeze

  def initialize(config:, access_log:, other_logs: {})
    @config = config
    @access_log = access_log
    @other_logs = other_logs
  end

  def errors
    @errors ||= [].tap do |failures|
      check_map(failures)
      check_log_format(failures)
      check_access_logs(failures)
      check_probe(failures)
      check_evidence(failures)
    end
  end

  private

  attr_reader :config, :access_log, :other_logs

  def active_config
    @active_config ||= config.lines.reject { |line| line.lstrip.start_with?('#') }.join
  end

  def check_map(failures)
    map = active_config[/map\s+\$uri\s+\$organizer_private_uri\s*\{.*?\}/m]
    unless map&.include?(FILTERED_PATH)
      failures << "effective nginx config does not map organizer paths to #{FILTERED_PATH}"
    end
  end

  def check_log_format(failures)
    format = active_config[/log_format\s+organizer_private\s+(.*?);/m, 1]
    unless format&.include?('$organizer_private_uri')
      failures << 'organizer_private log format is missing $organizer_private_uri'
      return
    end

    unsafe = UNSAFE_VARIABLES.select { |variable| format.match?(/#{Regexp.escape(variable)}(?![A-Za-z0-9_])/) }
    failures << "organizer_private log format includes unsafe variables: #{unsafe.join(', ')}" if unsafe.any?
  end

  def check_access_logs(failures)
    directives = active_config.scan(/access_log\s+([^;]+);/).flatten.reject { |value| value.strip == 'off' }
    failures << 'effective nginx config has no active access_log directive' if directives.empty?

    unsafe = directives.reject { |value| value.split.include?('organizer_private') }
    failures << "access_log directives do not all select organizer_private: #{unsafe.join('; ')}" if unsafe.any?
  end

  def check_probe(failures)
    return if access_log.include?(FILTERED_PATH)

    failures << "access-log sample does not contain the masked synthetic probe path #{FILTERED_PATH}"
  end

  def check_evidence(failures)
    { 'access log' => access_log }.merge(other_logs).each do |name, contents|
      failures << "#{name} contains the synthetic organizer token" if contents.downcase.include?(SYNTHETIC_TOKEN)
    end
  end
end
