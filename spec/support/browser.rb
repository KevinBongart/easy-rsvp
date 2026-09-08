require 'selenium-webdriver'

Capybara.server = :puma, { Silent: true }
Capybara.default_max_wait_time = 5
Capybara.save_path = Rails.root.join('tmp/screenshots')

Capybara.register_driver :headless_firefox do |app|
  options = Selenium::WebDriver::Firefox::Options.new
  options.add_argument('-headless')
  options.binary = ENV['FIREFOX_BINARY'] if ENV['FIREFOX_BINARY'].present?
  Capybara::Selenium::Driver.new(app, browser: :firefox, options: options)
end

RSpec.configure do |config|
  config.around(type: :system, js: true) do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  config.before(type: :system) { driven_by(:rack_test) }
  config.before(type: :system, js: true) do
    driven_by(:headless_firefox)
    page.current_window.resize_to(1400, 1000)
  end
end
