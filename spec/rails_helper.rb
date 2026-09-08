require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
abort 'Specs must run in RAILS_ENV=test' unless ENV['RAILS_ENV'] == 'test'

# Never borrow a developer's dashboard credentials or external service settings.
ENV['ADMIN_USER'] = 'spec-admin'
ENV['ADMIN_PASSWORD'] = 'spec-password'
ENV['AWS_EC2_METADATA_DISABLED'] = 'true'
ENV['S3_ACCESS_KEY_ID'] = 'test-access-key'
ENV['S3_SECRET_ACCESS_KEY'] = 'test-secret-key'
ENV['SCOUT_MONITOR'] = 'false'
require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)
require_relative '../config/environment'
require 'rspec/rails'
require 'capybara/rails'
require 'capybara/rspec'
require 'factory_bot_rails'

config = ActiveRecord::Base.connection_db_config
unless config.database == 'events_test' && [nil, '', 'localhost', '127.0.0.1', '::1'].include?(config.host)
  abort 'Specs require the local events_test database'
end
ActiveRecord::Migration.maintain_test_schema!

Rails.root.glob('spec/support/**/*.rb').sort.each { |file| require file }

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join('spec/fixtures')]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ActiveJob::TestHelper

  config.before do
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
    clear_performed_jobs
  end
  config.after { travel_back }
end
