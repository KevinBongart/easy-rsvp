class OrganizerLogPrivacyVerifier
  SYNTHETIC_TOKEN = '11111111-2222-4333-8444-555555555555'
  FILTERED_PATH = '/[FILTERED]/admin/[FILTERED]'
  FILTERED_PROBE_PATH = '/organizer-log-privacy-probe/admin/[FILTERED]'
  GENERAL_MAP_RULE = '~^/[^/]+/admin/ /[FILTERED]/admin/[FILTERED];'
  PROBE_MAP_RULE = '~^/organizer-log-privacy-probe/admin/ /organizer-log-privacy-probe/admin/[FILTERED];'
  FORMAT_VARIABLES = %w[
    $remote_addr
    $request_method
    $organizer_private_uri
    $status
    $body_bytes_sent
    $request_time
  ].freeze

  def initialize(http_config:, server_config:, access_log:, error_log:, other_logs: {})
    @http_config = http_config
    @server_config = server_config
    @access_log = access_log
    @error_log = error_log
    @other_logs = other_logs
  end

  def errors
    @errors ||= [].tap do |failures|
      check_map(failures)
      check_log_format(failures)
      check_server_config(failures)
      check_probe(failures)
      check_evidence(failures)
    end
  end

  private

  attr_reader :http_config, :server_config, :access_log, :error_log, :other_logs

  def active(config)
    config.lines.reject { |line| line.lstrip.start_with?('#') }.join
  end

  def check_map(failures)
    map = active(http_config)[/map\s+\$uri\s+\$organizer_private_uri\s*\{.*?\}/m]
    normalized_map = map&.gsub(/\s+/, ' ')

    failures << 'effective nginx config is missing the general organizer-path redaction rule' unless
      normalized_map&.include?(GENERAL_MAP_RULE)
    failures << 'effective nginx config is missing the identifiable synthetic-probe redaction rule' unless
      normalized_map&.include?(PROBE_MAP_RULE)
  end

  def check_log_format(failures)
    format = active(http_config)[/log_format\s+organizer_private\s+(.*?);/m, 1]
    variables = format&.scan(/\$[A-Za-z0-9_]+/)
    return if variables == FORMAT_VARIABLES

    failures << "organizer_private must use exactly these variables: #{FORMAT_VARIABLES.join(', ')}"
  end

  def check_server_config(failures)
    config = active(server_config)
    blocks = server_blocks(config)
    failures << 'Easy RSVP server config contains no server block' if blocks.empty?

    blocks.each_with_index do |block, index|
      server_names = block.scan(/server_name\s+([^;]+);/).flatten.flat_map(&:split)
      if server_names.empty?
        failures << "Easy RSVP server block #{index + 1} has no server_name directive"
      elsif server_names.any? { |name| name != 'easy-rsvp.com' && !name.end_with?('.easy-rsvp.com') }
        failures << 'server config includes a host outside easy-rsvp.com; supply only Easy RSVP server blocks'
      end

      server_logs = server_level_access_logs(block).reject { |value| value.strip == 'off' }
      if server_logs.none? { |value| value.split.include?('organizer_private') }
        failures << "Easy RSVP server block #{index + 1} must explicitly select organizer_private"
      end

      unsafe = block.scan(/access_log\s+([^;]+);/).flatten
        .reject { |value| value.strip == 'off' || value.split.include?('organizer_private') }
      failures << "Easy RSVP access_log directives do not all select organizer_private: #{unsafe.join('; ')}" if unsafe.any?
    end
  end

  def check_probe(failures)
    return if access_log.include?(FILTERED_PROBE_PATH)

    failures << "access-log sample does not contain the identifiable masked probe #{FILTERED_PROBE_PATH}"
  end

  def check_evidence(failures)
    evidence = { 'access log' => access_log, 'error log' => error_log }.merge(other_logs)
    evidence.each do |name, contents|
      normalized = contents.downcase.gsub('%2d', '-')
      failures << "#{name} contains the synthetic organizer token" if normalized.include?(SYNTHETIC_TOKEN)
    end
  end

  def server_blocks(config)
    blocks = []
    offset = 0

    while (match = /server\s*\{/.match(config, offset))
      opening = config.index('{', match.begin(0))
      closing = matching_brace(config, opening)
      break unless closing

      blocks << config[match.begin(0)..closing]
      offset = closing + 1
    end

    blocks
  end

  def matching_brace(config, opening)
    depth = 0
    quote = nil

    (opening...config.length).each do |index|
      character = config[index]
      if quote
        quote = nil if character == quote && config[index - 1] != '\\'
      elsif character == "'" || character == '"'
        quote = character
      elsif character == '{'
        depth += 1
      elsif character == '}'
        depth -= 1
        return index if depth.zero?
      end
    end

    nil
  end

  def server_level_access_logs(block)
    depth = 0
    block.each_line.filter_map do |line|
      active_line = line.sub(/#.*/, '')
      directive = active_line[/access_log\s+([^;]+);/, 1] if depth == 1
      depth += active_line.count('{') - active_line.count('}')
      directive
    end
  end
end
