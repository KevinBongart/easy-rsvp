require 'rails_helper'
require Rails.root.join('lib/organizer_log_privacy_verifier')

RSpec.describe OrganizerLogPrivacyVerifier do
  let(:safe_config) do
    <<~NGINX
      map $uri $organizer_private_uri {
        default $uri;
        ~^/[^/]+/admin/ /[FILTERED]/admin/[FILTERED];
      }
      log_format organizer_private '$request_method $organizer_private_uri $status';
      access_log /var/log/nginx/easy-rsvp-access.log organizer_private;
    NGINX
  end
  let(:safe_access_log) { "GET /[FILTERED]/admin/[FILTERED] 404\n" }

  it 'accepts effective config and log evidence with a masked synthetic probe' do
    verifier = described_class.new(
      config: safe_config,
      access_log: safe_access_log,
      other_logs: { 'collector sample' => 'request completed' }
    )

    expect(verifier.errors).to be_empty
  end

  it 'rejects access logs that retain a default unredacted format' do
    config = safe_config.sub(
      'access_log /var/log/nginx/easy-rsvp-access.log organizer_private;',
      "access_log /var/log/nginx/easy-rsvp-access.log organizer_private;\naccess_log /var/log/nginx/access.log;"
    )

    expect(described_class.new(config: config, access_log: safe_access_log).errors)
      .to include(a_string_including('do not all select organizer_private'))
  end

  it 'rejects raw request variables in the private format' do
    config = safe_config.sub('$request_method', '$request')

    expect(described_class.new(config: config, access_log: safe_access_log).errors)
      .to include(a_string_including('unsafe variables: $request'))
  end

  it 'rejects the synthetic token in any supplied log sink' do
    verifier = described_class.new(
      config: safe_config,
      access_log: safe_access_log,
      other_logs: { 'error log' => "failed #{described_class::SYNTHETIC_TOKEN}" }
    )

    expect(verifier.errors).to include('error log contains the synthetic organizer token')
  end

  it 'requires evidence that the synthetic organizer request reached the access log' do
    verifier = described_class.new(config: safe_config, access_log: 'GET / 200')

    expect(verifier.errors).to include(a_string_including('does not contain the masked synthetic probe path'))
  end
end
