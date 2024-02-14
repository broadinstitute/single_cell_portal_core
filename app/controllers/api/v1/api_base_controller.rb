module Api
  module V1
    class ApiBaseController < ActionController::API
      include Concerns::ContentType
      include Concerns::CspHeaderBypass
      include ActionController::MimeResponds
      include Concerns::IngestAware
      include Concerns::StudyAware
      include Concerns::Authenticator
      include Swagger::Blocks
      include ::RealIpLogger

      rescue_from ActionController::ParameterMissing do |exception|
        MetricsService.report_error(exception, request, current_api_user, @study)
        render json: { error: exception.message }, status: :bad_request
      end

      # always default to Api::V1::ExceptionsController for error rendering, regardless of environment
      # from https://github.com/rails/rails/blob/main/actionpack/lib/action_controller/metal/rescue.rb#L16
      def show_detailed_exceptions?
        false
      end

      ##
      # Generic message formatters to use in Swagger responses
      ##

      # HTTP 401 - User is not signed in
      def self.unauthorized
        'User is not authenticated'
      end

      # HTTP 403 - User is forbidden from performing action
      def self.forbidden(message)
        "User unauthorized to #{message}"
      end

      # HTTP 404 - Resource not found
      def self.not_found(*resources)
        "#{resources.join(', ')} not found"
      end

      # HTTP 406 - invalid response content type requested
      def self.not_acceptable
        '"Accept" header must contain "application/json", "text/plain", or "\*/\*"'
      end

      # HTTP 410 - Resource gone (this only happens when a Study workspace has been deleted)
      def self.resource_gone
        'Study workspace is not found, cannot complete action'
      end

      # HTTP 422 - Unprocessable entity; failed validation
      module SwaggerResponses
        module ValidationFailureResponse
          def self.extended(base)
            base.response 422 do
              key :description, 'Resource failed validation'
              schema do
                key :title, 'ValidationErrors'
                property :errors do
                  key :type, :array
                  key :description, 'Validation errors'
                  key :required, true
                  items do
                    key :type, :string
                    key :description, 'Error message'
                  end
                end
              end
            end
          end
        end
        # default responses for API endpoints that relate to a single study
        # (e.g. those under the api/v1/studies/ path)
        module StudyControllerResponses
          def self.extended(base)
            base.response 401 do
              key :description, ApiBaseController.unauthorized
            end
            base.response 404 do
              key :description, ApiBaseController.not_found(Study)
            end
            base.response 406 do
              key :description, ApiBaseController.not_acceptable
            end
            base.response 410 do
              key :description, ApiBaseController.resource_gone
            end
          end
        end
      end

      # HTTP 423 - Resource locked (e.g. StudyFile is parsing or being subsampled)
      def self.resource_locked(resource)
        "#{resource} is currently locked"
      end
    end
  end
end
