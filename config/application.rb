require_relative 'boot'

# require "rails"

# Pick the frameworks you want:
require "active_model/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_text/engine"

# require "action_cable/engine"
# require "action_mailbox/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module EasyRsvp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Keys for existing RSVP session cookies and persisted Action Text attachment
    # SGIDs were derived with SHA-1. Keep them readable until they have a migration path.
    config.active_support.key_generator_hash_digest_class = OpenSSL::Digest::SHA1

    # Rails enables YJIT in production. Keep a deploy-time off switch for hosts
    # where its executable-memory overhead exceeds the available headroom.
    config.yjit = false if ENV['RAILS_YJIT'] == 'false'

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.action_mailer.default_url_options = { host: ENV['DOMAIN'] }
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.perform_deliveries = true
    config.action_mailer.smtp_settings = {
      address: ENV['SMTP_SERVER'],
      user_name: ENV['SMTP_USERNAME'],
      password: ENV['SMTP_PASSWORD'],
      domain: ENV['DOMAIN'],
      port: 587,
      authentication: :plain,
      enable_starttls_auto: true
    }
  end
end
