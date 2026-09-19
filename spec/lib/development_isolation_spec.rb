require 'spec_helper'
require 'open3'
require 'json'

RSpec.describe 'Development storage isolation' do
  it 'maps imported S3 blobs to disk even with external settings present' do
    script = <<~'RUBY'
      require 'webmock'
      include WebMock::API
      WebMock.enable!
      WebMock.disable_net_connect!
      require_relative 'config/environment'
      services = %w[local amazon].map { |name| ActiveStorage::Blob.services.fetch(name).class.name }
      puts JSON.generate(service: Rails.configuration.active_storage.service, services: services)
    RUBY
    stdout, stderr, status = Open3.capture3(
      {'RAILS_ENV' => 'development', 'SCOUT_MONITOR' => 'false', 'AWS_EC2_METADATA_DISABLED' => 'true',
       'S3_ACCESS_KEY_ID' => 'synthetic', 'S3_SECRET_ACCESS_KEY' => 'synthetic'},
      'bundle', 'exec', 'ruby', '-e', script, chdir: File.expand_path('../..', __dir__)
    )
    expect(status.success?).to be(true), stderr
    result = JSON.parse(stdout.lines.last)
    expect(result).to eq('service' => 'local', 'services' => ['ActiveStorage::Service::DiskService'] * 2)
  end
end
