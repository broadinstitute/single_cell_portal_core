require "active_support/core_ext/integer/time"

# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  config.cache_classes = false

  # Do not eager load code on boot. This avoids loading your whole application
  # just for the purpose of running a single test. If you are using a tool that
  # preloads Rails for running tests, you may have to set it to true.
  config.eager_load = false

  # Configure public file server for tests with Cache-Control for performance.
  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    'Cache-Control' => "public, max-age=#{1.hour.to_i}"
  }

  # Show full error reports and disable caching.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true
  config.assets.compile = false
  config.assets.prefix = '/single_cell/test_assets'
  config.cache_store = :memory_store, {size: 2.gigabytes}

  # Raise exceptions instead of rendering exception templates.
  config.action_dispatch.show_exceptions = true

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  config.action_mailer.perform_caching = false

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raise exceptions for disallowed deprecations.
  config.active_support.disallowed_deprecation = :raise

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true
  if ENV['NOT_DOCKERIZED']
    config.action_controller.default_url_options = { :host => 'localhost', protocol: 'https', port: 3000 }
    config.action_controller.asset_host = 'localhost:3000'
  else
    config.action_controller.default_url_options = { :host => 'localhost', protocol: 'https' }
    config.action_controller.asset_host = 'localhost'
  end

  config.action_mailer.default_url_options = { :host => 'localhost', protocol: 'https' }
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = false
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.smtp_settings = {
    address:              'smtp.sendgrid.net',
    port:                 587,
    user_name:            ENV['SENDGRID_USERNAME'],
    password:             ENV['SENDGRID_PASSWORD'],
    domain:               'localhost',
    authentication:       'plain',
    enable_starttls_auto: true
  }

  config.disable_admin_notifications = true

  # set MongoDB & Google API logging level
  Mongoid.logger.level = Logger::INFO
  Google::Apis.logger.level = Logger::INFO

  config.bard_host_url = 'https://terra-bard-dev.appspot.com'

  # Terra Data Repo API base url
  config.tdr_api_base_url = 'https://jade.datarepo-dev.broadinstitute.org'

  # Enable profiling and flamegraphs via rack-mini-profiler
  config.profile_performance = false
end
