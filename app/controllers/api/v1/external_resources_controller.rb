module Api
  module V1
    class ExternalResourcesController < ApiBaseController

      before_action :authenticate_api_user!
      before_action :set_study
      before_action :check_study_permission
      before_action :set_external_resource, except: [:index, :create]

      respond_to :json

      swagger_path '/studies/{study_id}/external_resources' do
        operation :get do
          key :tags, [
              'ExternalResources'
          ]
          key :summary, 'Find all ExternalResources in a Study'
          key :description, 'Returns all ExternalResources for the given Study'
          key :operationId, 'study_external_resources_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Array of ExternalResource objects'
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'ExternalResource'
                key :'$ref', :ExternalResource
              end
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit ExternalResource')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      # GET /single_cell/api/v1/studies/:study_id
      def index
        @external_resources = @study.external_resources
      end

      swagger_path '/studies/{study_id}/external_resources/{id}' do
        operation :get do
          key :tags, [
              'ExternalResources'
          ]
          key :summary, 'Find an ExternalResource'
          key :description, 'Finds a single Study'
          key :operationId, 'study_external_resource_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of ExternalResource to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'ExternalResource object'
            schema do
              key :title, 'ExternalResource'
              key :'$ref', :ExternalResource
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, ExternalResource)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      # GET /single_cell/api/v1/studies/:study_id/external_resources/:id
      def show

      end

      swagger_path '/studies/{study_id}/external_resources' do
        operation :post do
          key :tags, [
              'ExternalResources'
          ]
          key :summary, 'Create an ExternalResource'
          key :description, 'Creates and returns a single ExternalResource'
          key :operationId, 'create_study_external_resource_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :external_resource
            key :in, :body
            key :description, 'ExternalResource object'
            key :required, true
            schema do
              key :'$ref', :ExternalResourceInput
            end
          end
          response 200 do
            key :description, 'Successful creation of ExternalResource object'
            schema do
              key :title, 'ExternalResource'
              key :'$ref', :ExternalResource
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          extend SwaggerResponses::ValidationFailureResponse
        end
      end

      # POST /single_cell/api/v1/studies/:study_id/external_resources
      def create
        @external_resource = @study.external_resources.build(external_resource_params)

        if @external_resource.save
          render :show
        else
          render json: {errors: @external_resource.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{study_id}/external_resources/{id}' do
        operation :patch do
          key :tags, [
              'ExternalResources'
          ]
          key :summary, 'Update an ExternalResource'
          key :description, 'Updates and returns a single ExternalResource.'
          key :operationId, 'update_study_external_resource_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of ExternalResource to update'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :external_resource
            key :in, :body
            key :description, 'ExternalResource object'
            key :required, true
            schema do
              key :'$ref', :ExternalResourceInput
            end
          end
          response 200 do
            key :description, 'Successful update of ExternalResource object'
            schema do
              key :title, 'ExternalResource'
              key :'$ref', :ExternalResource
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, ExternalResource)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          extend SwaggerResponses::ValidationFailureResponse
        end
      end

      # PATCH /single_cell/api/v1/studies/:study_id/external_resources/:id
      def update
        sanitized_update_params = external_resource_params.to_unsafe_hash.keep_if {|k,v| !v.blank?}
        if @external_resource.update(sanitized_update_params)
          render :show
        else
          render json: {errors: @external_resource.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{study_id}/external_resources/{id}' do
        operation :delete do
          key :tags, [
              'ExternalResources'
          ]
          key :summary, 'Delete an ExternalResource'
          key :description, 'Deletes a single ExternalResource'
          key :operationId, 'delete_study_external_resource_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of ExternalResource to delete'
            key :required, true
            key :type, :string
          end
          response 204 do
            key :description, 'Successful ExternalResource deletion'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('delete ExternalResource')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, ExternalResource)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      # DELETE /single_cell/api/v1/studies/:study_id/external_resources/:id
      def destroy
        begin
          @external_resource.destroy
          head 204
        rescue => e
          ErrorTracker.report_exception(e, current_api_user, @external_resource, params)
          MetricsService.report_error(e, request, current_api_user, @study)
          render json: {error: e.message}, status: 500
        end
      end

      private

      def set_study
        @study = Study.find_by(id: params[:study_id])
        if @study.nil? || @study.queued_for_deletion?
          head 404 and return
        end
      end

      def set_external_resource
        @external_resource = ExternalResource.find_by(id: params[:id])
        if @external_resource.nil?
          head 404 and return
        end
      end

      def check_study_permission
        head 403 unless @study.can_edit?(current_api_user)
      end

      # study file params list
      def external_resource_params
        params.require(:external_resource).permit(:id, :study_id, :title, :description, :url, :publication_url)
      end
    end
  end
end
