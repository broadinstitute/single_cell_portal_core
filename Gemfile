source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.4.2'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '6.1.7.9'
# Use SCSS for stylesheets
gem 'sass-rails', '>= 6'
# Use CoffeeScript for .coffee assets and views
gem 'coffee-rails'
# See https://github.com/rails/execjs#readme for more supported runtimes
# gem 'therubyracer', platforms: :ruby

# Use jquery as the JavaScript library
gem 'jquery-rails'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.7'
# bundle exec rake doc:rails generates the API under doc/api.
gem 'sdoc', group: :doc

# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use Unicorn as the app server
# gem 'unicorn'

# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development

gem 'bootsnap', require: false
gem 'minitest'
gem 'minitest-rails'
gem 'minitest-reporters'

gem 'devise'
gem 'omniauth-google-oauth2'
gem 'omniauth-rails_csrf_protection'
gem 'googleauth'
gem 'google-cloud-storage', require: 'google/cloud/storage'
gem 'google-cloud-bigquery', require: 'google/cloud/bigquery'
gem 'google-apis-lifesciences_v2beta', require: 'google/apis/lifesciences_v2beta'
gem 'google-apis-batch_v1', require: 'google/apis/batch_v1'
gem 'bootstrap-sass', :git => 'https://github.com/twbs/bootstrap-sass'
gem 'font-awesome-sass', git: 'https://github.com/FortAwesome/font-awesome-sass'
gem 'mongoid'
gem 'mongoid-history'
gem 'bson_ext'
gem 'delayed_job'
gem 'delayed_job_mongoid'
gem 'daemons'
gem 'nested_form', git: 'https://github.com/ryanb/nested_form'
gem 'jquery-datatables-rails', git: 'https://github.com/rweng/jquery-datatables-rails'
gem 'truncate_html'
gem 'jquery-fileupload-rails'
gem 'will_paginate_mongoid'
gem 'will_paginate'
gem 'will_paginate-bootstrap-style'
gem 'naturally'
gem 'rest-client'
gem 'mongoid-encrypted-fields'
gem 'gibberish'
gem 'parallel'
gem 'ruby_native_statistics'
gem 'mongoid_rails_migrations'
gem 'secure_headers'
gem 'swagger-blocks'
gem 'sentry-raven'
gem 'rubyzip'
gem 'rack-brotli'
gem 'time_difference'
gem 'sys-filesystem', require: 'sys/filesystem'
gem 'browser'
gem 'carrierwave', '~> 2.2'
gem 'carrierwave-mongoid', :require => 'carrierwave/mongoid'
gem 'uuid'
gem 'vite_rails'
gem 'net-smtp'
gem 'net-imap'
gem 'net-pop'
gem 'exponential-backoff'
gem 'concurrent-ruby', '1.3.4'
# gems removed from stdlib in 3.4
gem 'bigdecimal'
gem 'mutex_m'
gem 'observer'
gem 'ostruct'
gem 'logger'
gem 'benchmark'
gem 'drb'
gem 'reline'
gem 'irb'

group :development, :test do
  # Access an IRB console on exception pages or by using <%= console %> in views
  gem 'test-unit'
  gem 'brakeman', :require => false
  gem 'factory_bot_rails'
  gem 'listen'
  gem 'byebug'
  gem 'minitest-hooks'
  gem 'puma'
  gem 'rubocop', require: false
  gem 'rubocop-rails', require: false
  gem 'csv'

  # Profiling
  gem 'rack-mini-profiler'
  gem 'flamegraph'
  gem 'stackprof' # ruby 2.1+ only
  gem 'memory_profiler'
end

group :test do
  gem 'simplecov', require: false
  gem 'simplecov-lcov', require: false
end
