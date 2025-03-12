module Api
  module V1
    class StudySharesController < ApiBaseController
      before_action :authenticate_api_user!
      before_action :set_study
      before_action :check_study_permission
      before_action :set_study_share, except: [:index, :create]

      respond_to :json

      swagger_path '/studies/{study_id}/study_shares' do
        operation :get do
          key :tags, [
              'StudyShares'
          ]
          key :summary, 'Find all StudyShares in a Study'
          key :description, 'Returns all StudyShares for the given Study'
          key :operationId, 'study_study_shares_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Array of StudyShare objects'
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'StudyShare'
                key :'$ref', :StudyShare
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
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 410 do
            key :description, ApiBaseController.resource_gone
          end
        end
      end

      # GET /single_cell/api/v1/studies/:study_id
      def index
        @study_shares = @study.study_shares
      end

      swagger_path '/studies/{study_id}/study_shares/{id}' do
        operation :get do
          key :tags, [
              'StudyShares'
          ]
          key :summary, 'Find a StudyShare'
          key :description, 'Finds a single Study'
          key :operationId, 'study_study_share_path'
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
            key :description, 'ID of StudyShare to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'StudyShare object'
            schema do
              key :title, 'StudyShare'
              key :'$ref', :StudyShare
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, StudyShare)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 410 do
            key :description, ApiBaseController.resource_gone
          end
        end
      end

      # GET /single_cell/api/v1/studies/:study_id/study_shares/:id
      def show

      end

      swagger_path '/studies/{study_id}/study_shares' do
        operation :post do
          key :tags, [
              'StudyShares'
          ]
          key :summary, 'Create a StudyShare'
          key :description, 'Creates and returns a single StudyShare'
          key :operationId, 'create_study_study_share_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :study_share
            key :in, :body
            key :description, 'StudyShare object'
            key :required, true
            schema do
              key :'$ref', :StudyShareInput
            end
          end
          response 200 do
            key :description, 'Successful creation of StudyShare object'
            schema do
              key :title, 'StudyShare'
              key :'$ref', :StudyShare
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

      # POST /single_cell/api/v1/studies/:study_id/study_shares
      def create
        @study_share = @study.study_shares.build(study_share_params)

        if @study_share.save
          render :show
        else
          render json: {errors: @study_share.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{study_id}/study_shares/{id}' do
        operation :patch do
          key :tags, [
              'StudyShares'
          ]
          key :summary, 'Update a StudyShare'
          key :description, 'Updates and returns a single StudyShare.  Email address of share cannot be changed (you must create a new StudyShare for that).'
          key :operationId, 'update_study_study_share_path'
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
            key :description, 'ID of StudyShare to update'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :study_share
            key :in, :body
            key :description, 'StudyShare object'
            key :required, true
            schema do
              key :'$ref', :StudyShareUpdateInput
            end
          end
          response 200 do
            key :description, 'Successful update of StudyShare object'
            schema do
              key :title, 'StudyShare'
              key :'$ref', :StudyShare
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, StudyShare)
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

      # PATCH /single_cell/api/v1/studies/:study_id/study_shares/:id
      def update
        if @study_share.update(study_share_params)
          render :show
        else
          render json: {errors: @study_share.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{study_id}/study_shares/{id}' do
        operation :delete do
          key :tags, [
              'StudyShares'
          ]
          key :summary, 'Delete a StudyShare'
          key :description, 'Deletes a single StudyShare'
          key :operationId, 'delete_study_study_share_path'
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
            key :description, 'ID of StudyShare to delete'
            key :required, true
            key :type, :string
          end
          response 204 do
            key :description, 'Successful StudyShare deletion'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('delete Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, StudyShare)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 410 do
            key :description, ApiBaseController.resource_gone
          end
        end
      end

      # DELETE /single_cell/api/v1/studies/:study_id/study_shares/:id
      def destroy
        begin
          @study_share.destroy
          head 204
        rescue => e
          ErrorTracker.report_exception(e, current_api_user, @study_share, params)
          MetricsService.report_error(e, request, current_api_user, @study)
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

      def set_study_share
        @study_share = StudyShare.find_by(id: params[:id])
        if @study_share.nil?
          head 404 and return
        end
      end

      def check_study_permission
        head 403 unless @study.can_edit?(current_api_user)
      end

      # study file params list
      def study_share_params
        params.require(:study_share).permit(:id, :study_id, :email, :permission, :deliver_emails)
      end
    end
  end
end

