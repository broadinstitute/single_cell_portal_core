require_relative 'boot'

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
# require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
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
    config.load_defaults 5.0

    config.autoload_paths << Rails.root.join('lib')
    config.eager_load_paths << Rails.root.join('lib')
    config.autoload_paths << Rails.root.join('app/lib')
    config.eager_load_paths << Rails.root.join('app/lib')

    config.time_zone = 'Eastern Time (US & Canada)'

    config.middleware.use Rack::Deflater

    # Docker image for file parsing via scp-ingest-pipeline
    config.ingest_docker_image = 'gcr.io/broad-singlecellportal-staging/scp-ingest-pipeline:1.6.2'

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
  end
end
