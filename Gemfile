source 'https://rubygems.org'

git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby File.read('.ruby-version')

gem 'rails', '~> 8.1.3', '>= 8.1.3.1'

gem "aws-sdk-s3", require: false
gem 'bootsnap', require: false
gem 'cssbundling-rails'
gem 'hashid-rails'
gem 'image_processing', '~> 1.2'
gem 'importmap-rails'
gem 'jbuilder'
gem 'kaminari'
gem 'net-imap'
gem 'net-pop'
gem 'net-smtp'
gem 'octicons'
gem 'octicons_helper'
gem 'pg'
gem 'propshaft'
gem 'puma'
gem 'rollbar'
gem 'scout_apm'
gem 'simple_form'
gem 'stimulus-rails'
gem 'turbo-rails'

group :development, :test do
  gem 'brakeman', '~> 8.0', require: false
  gem 'bundler-audit', '~> 0.9', require: false
  gem 'byebug'
  gem 'capybara'
  gem 'dotenv-rails'
  gem 'launchy'
  gem 'rspec-rails'
  gem 'rspec_junit_formatter'
end

group :test do
  gem 'factory_bot_rails', '~> 6.4'
  gem 'selenium-webdriver', '~> 4.35'
  gem 'webmock', '~> 3.23'
end

group :development do
  gem 'listen'
  gem 'ruby-lsp'
  gem 'spring'
  gem 'spring-watcher-listen'
  gem 'web-console'
end
