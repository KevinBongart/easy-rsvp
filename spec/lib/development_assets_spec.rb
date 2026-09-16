require 'spec_helper'
require 'open3'
require 'json'

RSpec.describe 'Development asset delivery' do
  it 'serves Bootstrap, directly reloadable application CSS, and compiled JavaScript through Propshaft' do
    # Boot the actual development configuration: ordinary specs use test assets.
    script = <<~'RUBY'
      require_relative 'config/environment'
      require 'rack/mock'
      stylesheet_paths = %w[bootstrap actiontext admin_statistics application].to_h do |name|
        [name, ApplicationController.helpers.stylesheet_path(name)]
      end
      javascript_path = ApplicationController.helpers.javascript_path('application')
      request = Rack::MockRequest.new(Rails.application)
      stylesheets = stylesheet_paths.transform_values do |path|
        request.get(path, "HTTP_HOST" => "localhost")
      end
      javascript = request.get(javascript_path, "HTTP_HOST" => "localhost")
      puts JSON.generate(stylesheet_paths: stylesheet_paths,
                         stylesheet_statuses: stylesheets.transform_values(&:status),
                         bootstrap_styles: stylesheets['bootstrap'].body.include?('.btn-primary'),
                         application_styles: stylesheets['application'].body.include?('--bs-btn-color: #fff'),
                         chart_styles: stylesheets['admin_statistics'].body.include?('.admin-sparkline'),
                         javascript_path: javascript_path, javascript_status: javascript.status)
    RUBY
    stdout, stderr, status = Open3.capture3(
      { 'RAILS_ENV' => 'development', 'AWS_EC2_METADATA_DISABLED' => 'true', 'SCOUT_MONITOR' => 'false' },
      'bundle', 'exec', 'ruby', '-e', script, chdir: File.expand_path('../..', __dir__)
    )
    expect(status.success?).to be(true), stderr
    result = JSON.parse(stdout.lines.last)
    expect(result['stylesheet_paths'].values).to all(match(%r{\A/assets/[a-z_.]+-[0-9a-f]+\.css\z}))
    expect(result['stylesheet_statuses'].values).to all(eq(200))
    expect(result['bootstrap_styles']).to be(true)
    expect(result['application_styles']).to be(true)
    expect(result['chart_styles']).to be(true)
    expect(result['javascript_path']).to match(%r{\A/assets/application-[0-9a-f]+\.js\z})
    expect(result['javascript_status']).to eq(200)
  end
end
