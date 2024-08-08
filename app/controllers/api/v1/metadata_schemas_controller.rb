module Api
  module V1
    class MetadataSchemasController < ApiBaseController
      include Concerns::ConventionSchemas

      swagger_path '/metadata_schemas' do
        operation :get do
          key :tags, [
              'MetadataSchemas'
          ]
          key :summary, 'List all available metadata schemas'
          key :description, 'Returns a list of all available metadata schemas, by project & version'
          key :operationId, 'metadata_schemas_path'
          response 200 do
            key :description, 'list of available metadata convention schemas'
          end
        end
      end

      def index
        schemas = get_available_schemas
        render json: schemas
      end

      swagger_path '/metadata_schemas/{project_name}/{version}/{schema_format}' do
        operation :get do
          key :tags, [
              'MetadataSchemas'
          ]
          key :summary, 'Load a metadata convention schema file'
          key :description, "Returns a schema definition file for the requested metadata convention, in JSON or TSV format. Refer above for available schemas."
          key :operationId, 'metadata_schemas_load_schema_path'
          parameter do
            key :name, :project_name
            key :in, :path
            key :description, 'Project name of metadata convention'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :version
            key :in, :path
            key :description, 'Version of requested convention'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :schema_format
            key :in, :path
            key :description, 'File format of convention schema, either JSON or TSV'
            key :required, true
            key :enum, %w(json tsv)
            key :type, :string
          end
          response 200 do
            key :description, 'Metadata convention schema file in requested format'
          end
          response 404 do
            key :description, ApiBaseController.not_found('Convention Metadata Schema')
          end
          response 500 do
            key :description, 'Server error'
          end
        end
      end

      def load_schema
        # determine response type
        case params[:schema_format]
        when 'json'
          response_type = 'application/json'
        when 'tsv'
          response_type = 'text/plain'
        else
          response_type = 'application/json'
        end

        schema_info = validate_schema_params(params[:project_name], params[:version], params[:schema_format])
        if schema_info.present?
          send_file schema_info[:path], type: response_type, filename: schema_info[:filename]
        else
          head 404 and return
        end
      end
    end
  end
end

