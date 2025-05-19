Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  # Add data like request headers and IP for users, if applicable;
  # see https://docs.sentry.io/platforms/ruby/data-management/data-collected/ for more info
  config.send_default_pii = true
end
