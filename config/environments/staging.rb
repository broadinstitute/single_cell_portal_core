require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  config.action_controller.asset_host = ENV['PROD_HOSTNAME']
  config.assets.prefix = '/single_cell/assets'

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false
  config.action_controller.raise_on_missing_callback_actions = false


  # Mitigate X-Forwarded-Host injection attacks
  config.action_controller.default_url_options = { :host => ENV['PROD_HOSTNAME'], protocol: 'https' }

  # Mailer settings
  config.action_mailer.default_url_options = { :host => ENV['PROD_HOSTNAME'], protocol: 'https' }
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.smtp_settings = {
    address:              'smtp.sendgrid.net',
    port:                 2525,
    user_name:            ENV['SENDGRID_USERNAME'],
    password:             ENV['SENDGRID_PASSWORD'],
    domain:               ENV['PROD_HOSTNAME'],
    authentication:       'plain',
    enable_starttls_auto: true
  }

  # CUSTOM CONFIGURATION

  # disable admin notification (like startup email)
  config.disable_admin_notifications = true

  config.bard_host_url = 'https://terra-bard-dev.appspot.com'

  # Terra Data Repo API base url
  config.tdr_api_base_url = 'https://jade.datarepo-dev.broadinstitute.org'

  # Enable profiling and flamegraphs via rack-mini-profiler
  config.profile_performance = false

  # DNS rebinding/host header injection protection
  # CIDR ip ranges from https://cloud.google.com/load-balancing/docs/health-checks#firewall_rules
  config.hosts = [
    ENV['PROD_HOSTNAME'], # hostname for server
    IPAddr.new('10.128.0.0/24'), # connection on private network for LB health check
    IPAddr.new('35.191.0.0/16'), # external IP range for LB health check
    IPAddr.new('130.211.0.0/22'), # external IP range for LB health check
    IPAddr.new('209.85.152.0/22'), # external IP range for network LB
    IPAddr.new('209.85.204.0/22') # external IP range for network LB
  ]
end
