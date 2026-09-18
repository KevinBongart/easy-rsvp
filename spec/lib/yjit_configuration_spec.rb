require 'spec_helper'
require 'open3'

RSpec.describe 'YJIT configuration' do
  it 'provides a deploy-time opt-out' do
    script = "require_relative 'config/environment'; puts Rails.application.config.yjit"
    stdout, stderr, status = Open3.capture3(
      {
        'RAILS_ENV' => 'test',
        'RAILS_YJIT' => 'false',
        'AWS_EC2_METADATA_DISABLED' => 'true',
        'SCOUT_MONITOR' => 'false'
      },
      'bundle', 'exec', 'ruby', '-e', script, chdir: File.expand_path('../..', __dir__)
    )

    expect(status.success?).to be(true), stderr
    expect(stdout.lines.last.strip).to eq('false')
  end
end
