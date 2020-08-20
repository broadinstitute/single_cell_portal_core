Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join('tmp', 'caching-dev.txt').exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true

    config.cache_store = :memory_store
    config.public_file_server.headers = {
      'Cache-Control' => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  config.action_mailer.perform_caching = false

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Debug mode disables concatenation and preprocessing of assets.
  # This option may cause significant delays in view rendering with a large
  # number of complex assets.
  config.assets.debug = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Raises error for missing translations.
  # config.action_view.raise_on_missing_translations = true

  # Mitigate X-Forwarded-Host injection attacks
  config.action_controller.default_url_options = { :host => 'localhost', protocol: 'https'}
  config.action_controller.asset_host = ENV['NOT_DOCKERIZED'] ? 'localhost:3000' : 'localhost'

  # Use an evented file watcher to asynchronously detect changes in source code,
  # routes, locales, etc. This feature depends on the listen gem.
  config.file_watcher = ActiveSupport::EventedFileUpdateChecker

  config.bard_host_url = 'https://terra-bard-dev.appspot.com'


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

  # CUSTOM CONFIGURATION

  # disable admin notification (like startup email)
  config.disable_admin_notifications = false

  # set MongoDB & Google API logging level
  Mongoid.logger.level = Logger::INFO
  Google::Apis.logger.level = Logger::INFO

  # patching Devise sign_out method & SwaggerDocs to bypass CSP headers & layout fixes
  config.to_prepare do
    Devise::RegistrationsController.send(:include, DeviseSignOutPatch)
    SwaggerUiEngine::SwaggerDocsController.send(:include, Api::V1::Concerns::CspHeaderBypass)
    SwaggerUiEngine::SwaggerDocsController.send(:layout, 'swagger_ui_engine/layouts/swagger')
  end


  if ENV['NOT_DOCKERIZED']
    config.force_ssl = true
    config.ssl_options = {
      hsts: false # tell the browser NOT to cache this site a a mandatory https, for easier switching
    }
  end

  config.bard_host_url = 'https://terra-bard-dev.appspot.com'
end
