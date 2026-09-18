require 'spec_helper'
require 'open3'
require 'json'

RSpec.describe 'Development asset delivery' do
  it 'serves the current Dart Sass and JavaScript builds through Propshaft' do
    # Boot the actual development configuration: ordinary specs use test assets.
    script = <<~'RUBY'
      require_relative 'config/environment'
      require 'rack/mock'
      stylesheet_path = ApplicationController.helpers.stylesheet_path('application')
      javascript_path = ApplicationController.helpers.javascript_path('application')
      request = Rack::MockRequest.new(Rails.application)
      stylesheet = request.get(stylesheet_path, "HTTP_HOST" => "localhost")
      javascript = request.get(javascript_path, "HTTP_HOST" => "localhost")
      puts JSON.generate(manifest_path: Rails.application.config.assets.manifest_path.to_s,
                         stylesheet_path: stylesheet_path, stylesheet_status: stylesheet.status,
                         bootstrap_styles: stylesheet.body.include?('.btn-primary'),
                         white_primary_button: stylesheet.body.include?('--bs-btn-color: #fff'),
                         chart_styles: stylesheet.body.include?('.admin-sparkline'),
                         action_text_styles: stylesheet.body.include?('.trix-content'),
                         javascript_path: javascript_path, javascript_status: javascript.status)
    RUBY
    stdout, stderr, status = Open3.capture3(
      { 'RAILS_ENV' => 'development', 'AWS_EC2_METADATA_DISABLED' => 'true', 'SCOUT_MONITOR' => 'false' },
      'bundle', 'exec', 'ruby', '-e', script, chdir: File.expand_path('../..', __dir__)
    )
    expect(status.success?).to be(true), stderr
    result = JSON.parse(stdout.lines.last)
    expect(result['manifest_path']).to match(%r{/tmp/propshaft-development-\d+\.json\z})
    expect(result['stylesheet_path']).to match(%r{\A/assets/application-[0-9a-f]+\.css\z})
    expect(result['stylesheet_status']).to eq(200)
    expect(result['bootstrap_styles']).to be(true)
    expect(result['white_primary_button']).to be(true)
    expect(result['chart_styles']).to be(true)
    expect(result['action_text_styles']).to be(true)
    expect(result['javascript_path']).to match(%r{\A/assets/application-[0-9a-f]+\.js\z})
    expect(result['javascript_status']).to eq(200)
  end
end
