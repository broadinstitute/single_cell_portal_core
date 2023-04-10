source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.1.3'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '6.1.7.1'
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
gem 'minitest', '5.15.0'
gem 'minitest-rails'
gem 'minitest-reporters'

gem 'devise'
gem 'omniauth-google-oauth2'
gem 'omniauth-rails_csrf_protection'
gem 'googleauth'
gem 'google-cloud-storage', require: 'google/cloud/storage'
gem 'google-cloud-bigquery', require: 'google/cloud/bigquery'
gem 'google-api-client', require: 'google/apis/genomics_v2alpha1'
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
gem 'ruby-prof'
gem 'ruby-prof-flamegraph'
gem 'carrierwave', '~> 2.0'
gem 'carrierwave-mongoid', :require => 'carrierwave/mongoid'
gem 'uuid'
gem 'vite_rails'
gem 'net-smtp'
gem 'net-imap'
gem 'net-pop'
gem 'exponential-backoff'

# only enable TCell in deployed environments due to Chrome sec-ch-ua header issue
group :production, :staging do
  gem 'tcell_agent'
end

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
