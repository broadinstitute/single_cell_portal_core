module Api
  module V1
    class StatusController < ApiBaseController
      skip_before_action :validate_content_type!

      respond_to :json

      swagger_path '/status' do
        operation :get do
          key :tags, [
              'Status'
          ]
          key :summary, 'API Status Endpoint'
          key :description, 'Current API Status'
          response 200 do
            key :description, 'API is functioning normally'
          end
          response 500 do
            key :description, 'Internal server error'
          end
          response 503 do
            key :description, 'Service unavailable, usually due to scheduled deployment'
          end
        end
      end

      def index
        head 200
      end
    end
  end
end
