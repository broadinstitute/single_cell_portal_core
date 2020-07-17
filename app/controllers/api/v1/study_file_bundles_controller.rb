module Api
  module V1
    class StudyFileBundlesController < ApiBaseController
      include Concerns::Authenticator
      include Swagger::Blocks

      before_action :authenticate_api_user!
      before_action :set_study
      before_action :check_study_permission
      before_action :set_study_file_bundle, except: [:index, :create]

      respond_to :json

      swagger_path '/studies/{study_id}/study_file_bundles' do
        operation :get do
          key :tags, [
              'StudyFileBundles'
          ]
          key :summary, 'Find all StudyFileBundles in a Study'
          key :description, "Returns all StudyFileBundles for the given Study.  A StudyFileBundle is an object that is used to associate multiple StudyFiles that are only valid when used together:  ```#{StudyFileBundle.swagger_requirements.html_safe}```"
          key :operationId, 'study_study_file_bundles_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Array of StudyFileBundle objects'
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'StudyFileBundle'
                key :'$ref', :StudyFileBundle
              end
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
          response 410 do
            key :description, ApiBaseController.resource_gone
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      # GET /single_cell/api/v1/studies/:study_id/study_file_bundles
      def index
        @study_file_bundles = @study.study_file_bundles
      end

      swagger_path '/studies/{study_id}/study_file_bundles/{id}' do
        operation :get do
          key :tags, [
              'StudyFileBundles'
          ]
          key :summary, 'Find a StudyFileBundle'
          key :description, 'Finds a single Study'
          key :operationId, 'study_study_file_bundle_path'
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
            key :description, 'ID of StudyFileBundle to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'StudyFileBundle object'
            schema do
              key :title, 'StudyFileBundle'
              key :'$ref', :StudyFileBundle
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, StudyFileBundle)
          end
          response 410 do
            key :description, ApiBaseController.resource_gone
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      # GET /single_cell/api/v1/studies/:study_id/study_file_bundles/:id
      def show

      end

      swagger_path '/studies/{study_id}/study_file_bundles' do
        operation :post do
          key :tags, [
              'StudyFileBundles'
          ]
          key :summary, 'Create a StudyFileBundle'
          key :description, 'Creates and returns a single StudyFileBundle'
          key :operationId, 'create_study_study_file_bundle_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :study_file_bundle
            key :in, :body
            key :description, 'StudyFileBundle object'
            key :required, true
            schema do
              key :'$ref', :StudyFileBundleInput
            end
          end
          response 200 do
            key :description, 'Successful creation of StudyFileBundle object'
            schema do
              key :title, 'StudyFileBundle'
              key :'$ref', :StudyFileBundle
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
          response 410 do
            key :description, ApiBaseController.resource_gone
          end
          extend SwaggerResponses::ValidationFailureResponse
        end
      end


      # POST /single_cell/api/v1/studies/:study_id/study_file_bundles
      def create
        @study_file_bundle = @study.study_file_bundles.build(study_file_bundle_params)

        if @study_file_bundle.save
          render :show
        else
          render json: {errors: @study_file_bundle.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{study_id}/study_file_bundles/{id}' do
        operation :delete do
          key :tags, [
              'StudyFileBundles'
          ]
          key :summary, 'Delete a StudyFileBundle'
          key :description, 'Deletes a single StudyFileBundle'
          key :operationId, 'delete_study_study_file_bundle_path'
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
            key :description, 'ID of StudyFileBundle to delete'
            key :required, true
            key :type, :string
          end
          response 204 do
            key :description, 'Successful StudyFileBundle deletion'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, StudyFileBundle)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 410 do
            key :description, ApiBaseController.resource_gone
          end
        end
      end

      # DELETE /single_cell/api/v1/studies/:study_id/study_file_bundles/:id
      def destroy
        begin
          @study_file_bundle.destroy
          head 204
        rescue => e
          error_context = ErrorTracker.format_extra_context(@study_file_bundle, {params: params})
          ErrorTracker.report_exception(e, current_api_user, error_context)
          render json: {error: e.message}, status: 500
        end
      end

      private

      def set_study
        @study = Study.find_by(id: params[:study_id])
        if @study.nil? || @study.queued_for_deletion?
          head 404 and return
        elsif @study.detached?
          head 410 and return
        end
      end

      def set_study_file_bundle
        @study_file_bundle = StudyFileBundle.find_by(id: params[:id])
        if @study_file_bundle.nil?
          head 404 and return
        end
      end

      def check_study_permission
        head 403 # unless @study.can_edit?(current_api_user)
      end

      # study file params whitelist
      def study_file_bundle_params
        params.require(:study_file_bundle).permit(:bundle_type, original_file_list: [:name, :file_type, :species, :assembly])
      end
    end
  end
end

