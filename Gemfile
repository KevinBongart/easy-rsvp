source "https://rubygems.org"

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby File.read(".ruby-version")

gem "rails", "~> 8.1.3", ">= 8.1.3.1"

gem "aws-sdk-s3", require: false
gem "bootsnap", require: false
gem "dartsass-rails", "~> 0.5.1"
gem "hashid-rails"
gem "honeybadger", "~> 6.9"
gem "icalendar", "~> 2.12"
gem "jsbundling-rails"
gem "kaminari"
gem "pg"
gem "propshaft"
gem "puma"
gem "scout_apm"
gem "simple_form"
gem "stimulus-rails"
gem "turbo-rails"

group :development, :test do
  gem "brakeman", "~> 8.0", require: false
  gem "bundler-audit", "~> 0.9", require: false
  gem "byebug"
  gem "capybara"
  gem "dotenv-rails"
  gem "erb_lint", "~> 0.9", require: false
  gem "launchy"
  gem "rspec-rails"
  gem "rspec_junit_formatter"
  gem "rubocop-rails-omakase", require: false
end

group :test do
  gem "axe-core-rspec", "~> 4.13"
  gem "factory_bot_rails", "~> 6.4"
  gem "selenium-webdriver", "~> 4.49"
  gem "webmock", "~> 3.23"
end

group :development do
  gem "listen"
  gem "ruby-lsp"
  gem "spring"
  gem "spring-watcher-listen"
  gem "web-console"
end
