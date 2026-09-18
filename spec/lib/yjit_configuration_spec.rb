require 'spec_helper'
require 'open3'
require 'json'

RSpec.describe 'YJIT configuration' do
  def production_yjit_settings(yjit_value)
    script = <<~'RUBY'
      require 'json'
      require_relative 'config/environment'
      puts JSON.generate(configured: Rails.application.config.yjit, enabled: RubyVM::YJIT.enabled?)
    RUBY
    stdout, stderr, status = Open3.capture3(
      {
        'RAILS_ENV' => 'production',
        'RAILS_YJIT' => yjit_value,
        'SECRET_KEY_BASE_DUMMY' => '1',
        'DOMAIN' => 'example.test',
        'AWS_EC2_METADATA_DISABLED' => 'true',
        'S3_ACCESS_KEY_ID' => 'test-access-key',
        'S3_SECRET_ACCESS_KEY' => 'test-secret-key',
        'SCOUT_MONITOR' => 'false'
      },
      'bundle', 'exec', 'ruby', '-e', script, chdir: File.expand_path('../..', __dir__)
    )

    expect(status.success?).to be(true), stderr
    JSON.parse(stdout.lines.last)
  end

  it 'uses the Rails 8.1 production default' do
    expect(production_yjit_settings(nil)).to eq('configured' => true, 'enabled' => true)
  end

  it 'provides a deploy-time production opt-out' do
    expect(production_yjit_settings('false')).to eq('configured' => false, 'enabled' => false)
  end
end
