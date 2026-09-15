require 'spec_helper'
require 'open3'
require 'json'

RSpec.describe 'Development asset delivery' do
  it 'serves the current compiled chart styles through Propshaft' do
    # Boot the actual development configuration: ordinary specs use test assets.
    script = <<~'RUBY'
      require_relative 'config/environment'
      require 'rack/mock'
      path = ApplicationController.helpers.stylesheet_path('application')
      response = Rack::MockRequest.new(Rails.application).get(path, "HTTP_HOST" => "localhost")
      puts JSON.generate(path: path, status: response.status,
                         chart_styles: response.body.include?('.admin-sparkline'))
    RUBY
    stdout, stderr, status = Open3.capture3(
      { 'RAILS_ENV' => 'development', 'AWS_EC2_METADATA_DISABLED' => 'true', 'SCOUT_MONITOR' => 'false' },
      'bundle', 'exec', 'ruby', '-e', script, chdir: File.expand_path('../..', __dir__)
    )
    expect(status.success?).to be(true), stderr
    result = JSON.parse(stdout.lines.last)
    expect(result['path']).to match(%r{\A/assets/application-[0-9a-f]+\.css\z})
    expect(result['status']).to eq(200)
    expect(result['chart_styles']).to be(true)
  end
end
