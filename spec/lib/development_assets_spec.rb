require 'spec_helper'
require 'open3'
require 'json'

RSpec.describe 'Development asset delivery' do
  it 'serves the current compiled CSS and JavaScript through Propshaft' do
    # Boot the actual development configuration: ordinary specs use test assets.
    script = <<~'RUBY'
      require_relative 'config/environment'
      require 'rack/mock'
      stylesheet_path = ApplicationController.helpers.stylesheet_path('application')
      javascript_path = ApplicationController.helpers.javascript_path('application')
      request = Rack::MockRequest.new(Rails.application)
      stylesheet = request.get(stylesheet_path, "HTTP_HOST" => "localhost")
      javascript = request.get(javascript_path, "HTTP_HOST" => "localhost")
      puts JSON.generate(stylesheet_path: stylesheet_path, stylesheet_status: stylesheet.status,
                         chart_styles: stylesheet.body.include?('.admin-sparkline'),
                         javascript_path: javascript_path, javascript_status: javascript.status,
                         bootstrap_5: javascript.body.include?('VERSION = "5.3.8"'),
                         trix: javascript.body.include?('window.Trix'))
    RUBY
    stdout, stderr, status = Open3.capture3(
      { 'RAILS_ENV' => 'development', 'AWS_EC2_METADATA_DISABLED' => 'true', 'SCOUT_MONITOR' => 'false' },
      'bundle', 'exec', 'ruby', '-e', script, chdir: File.expand_path('../..', __dir__)
    )
    expect(status.success?).to be(true), stderr
    result = JSON.parse(stdout.lines.last)
    expect(result['stylesheet_path']).to match(%r{\A/assets/application-[0-9a-f]+\.css\z})
    expect(result['stylesheet_status']).to eq(200)
    expect(result['chart_styles']).to be(true)
    expect(result['javascript_path']).to match(%r{\A/assets/application-[0-9a-f]+\.js\z})
    expect(result['javascript_status']).to eq(200)
    expect(result['bootstrap_5']).to be(true)
    expect(result['trix']).to be(true)
  end
end
