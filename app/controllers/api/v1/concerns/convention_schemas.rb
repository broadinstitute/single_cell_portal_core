module Api
  module V1
    module Concerns
      module ConventionSchemas
        extend ActiveSupport::Concern

        SCHEMAS_BASE_DIR = Rails.root.join('lib', 'assets', 'metadata_schemas')

        # load available metadata convention schemas from libdir
        def get_available_schemas
          schemas = {}
          projects = Dir.entries(SCHEMAS_BASE_DIR).delete_if {|entry| entry.start_with?('.')}
          projects.each do |project_name|
            snapshots_path = SCHEMAS_BASE_DIR + "#{project_name}/snapshot"
            snapshots = Dir.entries(snapshots_path).delete_if {|entry| entry.start_with?('.')}
            versions = %w(latest) + Naturally.sort(snapshots).reverse
            schemas[project_name] = versions
          end
          schemas
        end

        # get the latest version number of a given project/schema
        def get_latest_schema_version(project_name)
          schemas = get_available_schemas
          versions = schemas[project_name]
          # ampersand (&) notation will exit if at any point this evaluates to nil
          # e.g. get_latest_schema_version('does_not_exist') == nil
          versions&.delete_if {|version| version == 'latest'}&.first
        end
      end
    end
  end
end
