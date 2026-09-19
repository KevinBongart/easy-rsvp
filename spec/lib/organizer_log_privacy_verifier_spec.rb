require 'rails_helper'
require Rails.root.join('lib/organizer_log_privacy_verifier')

RSpec.describe OrganizerLogPrivacyVerifier do
  let(:safe_http_config) do
    <<~NGINX
      map $uri $organizer_private_uri {
        default $uri;
        ~^/organizer-log-privacy-probe/admin/ /organizer-log-privacy-probe/admin/[FILTERED];
        ~^/[^/]+/admin/ /[FILTERED]/admin/[FILTERED];
      }
      log_format organizer_private '$remote_addr $request_method $organizer_private_uri '
                                   '$status $body_bytes_sent $request_time';
    NGINX
  end
  let(:safe_server_config) do
    <<~NGINX
      server {
        server_name easy-rsvp.com www.easy-rsvp.com;
        access_log /var/log/nginx/easy-rsvp-access.log organizer_private;
      }
    NGINX
  end
  let(:safe_access_log) { "GET /organizer-log-privacy-probe/admin/[FILTERED] 404\n" }
  let(:safe_error_log) { 'request completed without an nginx error' }

  it 'accepts scoped Easy RSVP config and supplied log evidence with an identifiable probe' do
    expect(verifier(other_logs: { 'collector sample' => 'request completed' }).errors).to be_empty
  end

  it 'rejects access logs that retain a default unredacted format' do
    server_config = safe_server_config.sub(
      'access_log /var/log/nginx/easy-rsvp-access.log organizer_private;',
      "access_log /var/log/nginx/easy-rsvp-access.log organizer_private;\naccess_log /var/log/nginx/access.log;"
    )

    expect(verifier(server_config: server_config).errors)
      .to include(a_string_including('do not all select organizer_private'))
  end

  %w[$request $request_uri $uri $document_uri $args $query_string $http_referer].each do |variable|
    it "rejects #{variable} in the private format" do
      config = safe_http_config.sub('$request_time', "$request_time #{variable}")

      expect(verifier(http_config: config).errors)
        .to include(a_string_including('must use exactly these variables'))
    end
  end

  it 'rejects a map that redacts only the synthetic probe' do
    config = safe_http_config.sub('~^/[^/]+/admin/ /[FILTERED]/admin/[FILTERED];', '')

    expect(verifier(http_config: config).errors)
      .to include('effective nginx config is missing the general organizer-path redaction rule')
  end

  it 'rejects a server artifact containing another virtual host' do
    server_config = safe_server_config + <<~NGINX
      server {
        server_name unrelated.example;
        access_log /var/log/nginx/unrelated.log organizer_private;
      }
    NGINX

    expect(verifier(server_config: server_config).errors)
      .to include(a_string_including('supply only Easy RSVP server blocks'))
  end

  it 'rejects an app server that would inherit its access log configuration' do
    server_config = safe_server_config.sub(/\s*access_log .*?;\n/, "\n")

    expect(verifier(server_config: server_config).errors)
      .to include('Easy RSVP server block 1 must explicitly select organizer_private')
  end

  it 'checks every Easy RSVP server block for an explicit private access log' do
    inherited_server = <<~NGINX
      server {
        server_name www.easy-rsvp.com;
        location / { proxy_pass http://app; }
      }
    NGINX

    expect(verifier(server_config: safe_server_config + inherited_server).errors)
      .to include('Easy RSVP server block 2 must explicitly select organizer_private')
  end

  it 'rejects the synthetic token in mandatory or additional log evidence' do
    expect(verifier(error_log: "failed #{described_class::SYNTHETIC_TOKEN}").errors)
      .to include('error log contains the synthetic organizer token')
    expect(verifier(other_logs: { 'collector sample' => "failed #{described_class::SYNTHETIC_TOKEN}" }).errors)
      .to include('collector sample contains the synthetic organizer token')
  end

  it 'rejects a percent-encoded synthetic token' do
    token = described_class::SYNTHETIC_TOKEN.gsub('-', '%2D')

    expect(verifier(error_log: token).errors)
      .to include('error log contains the synthetic organizer token')
  end

  it 'requires evidence tied to the identifiable synthetic request' do
    expect(verifier(access_log: "GET #{described_class::FILTERED_PATH} 404").errors)
      .to include(a_string_including('does not contain the identifiable masked probe'))
  end

  def verifier(overrides = {})
    described_class.new(
      http_config: safe_http_config,
      server_config: safe_server_config,
      access_log: safe_access_log,
      error_log: safe_error_log,
      **overrides
    )
  end
end
