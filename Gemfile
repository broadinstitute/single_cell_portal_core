source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.4.8'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '7.1.6'
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

gem 'bootstrap-sass', git: 'https://github.com/twbs/bootstrap-sass'
gem 'browser'
gem 'bson_ext'
gem 'carrierwave', '~> 2.2'
gem 'carrierwave-mongoid', require: 'carrierwave/mongoid'
gem 'concurrent-ruby', '1.3.4'
gem 'daemons'
gem 'delayed_job'
gem 'delayed_job_mongoid'
gem 'devise', '~> 4.9'
gem 'exponential-backoff'
gem 'font-awesome-sass', git: 'https://github.com/FortAwesome/font-awesome-sass'
gem 'gibberish'
gem 'google-apis-batch_v1', require: 'google/apis/batch_v1'
gem 'googleauth'
gem 'google-cloud-storage', require: 'google/cloud/storage'
gem 'jquery-datatables-rails', git: 'https://github.com/rweng/jquery-datatables-rails'
gem 'jquery-fileupload-rails'
gem 'mongoid'
gem 'mongoid-encrypted-fields'
gem 'mongoid-history'
gem 'mongoid_rails_migrations'
gem 'naturally'
gem 'nested_form', git: 'https://github.com/ryanb/nested_form'
gem 'net-imap'
gem 'net-pop'
gem 'net-smtp'
gem 'omniauth-google-oauth2'
gem 'omniauth-rails_csrf_protection'
gem 'parallel'
gem 'rack-brotli'
gem 'rest-client'
gem 'ruby_native_statistics'
gem 'rubyzip'
gem 'secure_headers'
gem 'sentry-rails'
gem 'sentry-ruby'
gem 'swagger-blocks'
gem 'sys-filesystem', require: 'sys/filesystem'
gem 'time_difference'
gem 'truncate_html'
gem 'uuid'
gem 'vite_rails'
gem 'will_paginate'
gem 'will_paginate-bootstrap-style'
gem 'will_paginate_mongoid'
# gems removed from stdlib in 3.4
gem 'benchmark'
gem 'bigdecimal'
gem 'drb'
gem 'faraday-multipart', require: 'faraday/multipart'
gem 'irb'
gem 'json_schemer'
gem 'logger'
gem 'mutex_m'
gem 'observer'
gem 'ostruct'
gem 'reline'

group :development, :test do
  # Access an IRB console on exception pages or by using <%= console %> in views
  gem 'brakeman', require: false
  gem 'byebug'
  gem 'csv'
  gem 'factory_bot_rails'
  gem 'listen'
  gem 'minitest-hooks'
  gem 'puma'
  gem 'rubocop', require: false
  gem 'rubocop-rails', require: false
  gem 'test-unit'

  # Profiling
  gem 'flamegraph'
  gem 'memory_profiler'
  gem 'openssl'
  gem 'rack-mini-profiler'
  gem 'stackprof' # ruby 2.1+ only
end

group :test do
  gem 'simplecov', require: false
  gem 'simplecov-lcov', require: false
end
