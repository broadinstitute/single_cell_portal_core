require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
# require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "sprockets/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SingleCellPortal
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.1

    config.time_zone = 'Eastern Time (US & Canada)'

    config.middleware.use Rack::Brotli

    # Docker image for file parsing via scp-ingest-pipeline
    config.ingest_docker_image = 'gcr.io/broad-singlecellportal-staging/scp-ingest-pipeline:1.26.0'

    config.autoload_paths << Rails.root.join('lib')

    # for all non-prod environments, use the development mixpanel API
    config.mixpanel_service_account = 'scp_terra_dev.f25a4f.mp-service-account'
    config.mixpanel_project_id = 2085496

    # custom exceptions handling to render responses based on controller
    # uncaught API errors will now render as JSON responses w/ 500 status
    # normal controller errors will show 500 page, except in development environment (will show normal error page)
    # lambda allows for inspecting environment, which will include request parameters
    config.exceptions_app = lambda do |env|
      if env['action_dispatch.original_path']&.include?('api/v1')
        Api::V1::ExceptionsController.action(:render_error).call(env)
      else
        ExceptionsController.action(:render_error).call(env)
      end
    end
    # Google OAuth2 Scopes
    # basic scopes are user profile, email, and openid, and do not require user consent to request during auth handshake
    BASIC_GOOGLE_SCOPES = %w(email profile userinfo.email userinfo.profile openid)
  end
end
