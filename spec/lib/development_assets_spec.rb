require 'spec_helper'
require 'open3'
require 'json'

RSpec.describe 'Development asset delivery' do
  it 'serves current chart styles even when a precompiled manifest points to an older stylesheet' do
    # Boot the actual development configuration: test deliberately bypasses the
    # manifest, so ordinary browser specs cannot reproduce this failure.
    script = <<~'RUBY'
      require_relative 'config/environment'
      require 'rack/mock'
      Rails.application.assets_manifest.assets['application.css'] = 'application-stale.css'
      path = ApplicationController.helpers.stylesheet_path('application')
      response = Rack::MockRequest.new(Rails.application.assets).get(path.delete_prefix('/assets'))
      puts JSON.generate(path: path, status: response.status,
                         chart_styles: response.body.include?('.admin-sparkline'))
    RUBY
    stdout, stderr, status = Open3.capture3(
      { 'RAILS_ENV' => 'development', 'AWS_EC2_METADATA_DISABLED' => 'true', 'SCOUT_MONITOR' => 'false' },
      'bundle', 'exec', 'ruby', '-e', script, chdir: File.expand_path('../..', __dir__)
    )
    expect(status.success?).to be(true), stderr
    result = JSON.parse(stdout.lines.last)
    expect(result['path']).not_to include('application-stale.css')
    expect(result['status']).to eq(200)
    expect(result['chart_styles']).to be(true)
  end
end
