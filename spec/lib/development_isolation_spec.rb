require 'spec_helper'
require 'open3'
require 'json'

RSpec.describe 'Development storage and email isolation' do
  it 'maps imported S3 blobs to disk and captures email locally even with external settings present' do
    script = <<~'RUBY'
      require 'webmock'
      include WebMock::API
      WebMock.enable!
      WebMock.disable_net_connect!
      require_relative 'config/environment'
      require 'tmpdir'
      services = %w[local amazon].map { |name| ActiveStorage::Blob.services.fetch(name).class.name }
      method = ActionMailer::Base.delivery_method
      files = []
      if method == :file
        Dir.mktmpdir do |directory|
          ActionMailer::Base.file_settings = {location: directory}
          LocalPreviewMailer = Class.new(ActionMailer::Base) do
            def preview
              mail(to: 'preview@example.test', from: 'app@example.test', subject: 'Local preview', body: 'Local only')
            end
          end
          LocalPreviewMailer.preview.deliver_now
          files = Dir.glob("#{directory}/*").map { |path| File.read(path).include?('Local only') }
        end
      end
      puts JSON.generate(service: Rails.configuration.active_storage.service, services: services,
                         delivery: method, captured: files)
    RUBY
    stdout, stderr, status = Open3.capture3(
      {'RAILS_ENV' => 'development', 'SCOUT_MONITOR' => 'false', 'AWS_EC2_METADATA_DISABLED' => 'true',
       'S3_ACCESS_KEY_ID' => 'synthetic', 'S3_SECRET_ACCESS_KEY' => 'synthetic', 'SMTP_SERVER' => 'smtp.example.test'},
      'bundle', 'exec', 'ruby', '-e', script, chdir: File.expand_path('../..', __dir__)
    )
    expect(status.success?).to be(true), stderr
    result = JSON.parse(stdout.lines.last)
    expect(result).to eq('service' => 'local', 'services' => ['ActiveStorage::Service::DiskService'] * 2,
                        'delivery' => 'file', 'captured' => [true])
  end
end
