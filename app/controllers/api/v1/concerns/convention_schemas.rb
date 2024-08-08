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

        # take user params and determine if requested schema file exists
        def validate_schema_params(project, version, schema_format)
          schemas = get_available_schemas
          projects = schemas.keys
          return nil unless projects.include? project

          versions = schemas[project]
          return nil unless versions.include? version

          return nil unless %w[json tsv].include? schema_format

          schema_filename = sanitized_filename("#{project}_schema.#{schema_format}")
          schema_pathname = SCHEMAS_BASE_DIR + project
          schema_pathname += "snapshot/#{version}" if version != 'latest'

          { path: "#{schema_pathname}/#{schema_filename}", filename: schema_filename }
        end

        # properly sanitize filename before calling send_file
        # from https://api.rubyonrails.org/classes/ActiveStorage/Filename.html#method-i-sanitized
        def sanitized_filename(filename)
          filename.encode(
            Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�"
          ).strip.tr("\u{202E}%$|:;/\t\r\n\\", "-")
        end
      end
    end
  end
end
