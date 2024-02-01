module Api
  module V1
    # scaffold controller for CRUDing user saved views
    class SavedViewsController < ApiBaseController
      before_action :authenticate_api_user!
      before_action :set_saved_view, only: %i[show update destroy]
      before_action :check_saved_view_permissions, only: %i[show update destroy]

      respond_to :json

      swagger_path '/saved_views' do
        operation :get do
          key :tags, [
            'SavedViews'
          ]
          key :summary, 'Get my SavedViews'
          key :description, 'Returns all SavedViews for the given User'
          key :operationId, 'saved_views_path'
          response 200 do
            key :description, 'Array of SavedViews objects'
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'SavedView'
                key :'$ref', :SavedView
              end
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view SavedViews')
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def index
        @saved_views = current_api_user.saved_views
      end

      swagger_path '/saved_views/{id}' do
        operation :get do
          key :tags, [
            'SavedViews'
          ]
          key :summary, 'Find a SavedView'
          key :description, 'Finds a single SavedView for the given User'
          key :operationId, 'saved_view_path'
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of SavedView to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'SavedView object'
            schema do
              key :title, 'SavedView'
              key :'$ref', :SavedView
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('access SavedView')
          end
          response 404 do
            key :description, ApiBaseController.not_found(SavedView)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def show; end

      swagger_path '/saved_views' do
        operation :post do
          key :tags, [
            'SavedViews'
          ]
          key :summary, 'Create a SavedView'
          key :description, 'Creates and returns a single SavedView'
          key :operationId, 'create_saved_view_path'
          parameter do
            key :name, :saved_view
            key :in, :body
            key :description, 'SavedView object'
            key :required, true
            schema do
              key :'$ref', :SavedViewInput
            end
          end
          response 200 do
            key :description, 'Successful creation of SavedView object'
            schema do
              key :title, 'SavedView'
              key :'$ref', :SavedView
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          extend SwaggerResponses::ValidationFailureResponse
        end
      end

      def create
        @saved_view = SavedView.new(saved_view_params)
        @saved_view.user = current_api_user

        if @saved_view.save
          render :show, status: :ok
        else
          render json: { errors: @saved_view.errors }, status: :unprocessable_entity
        end
      end

      swagger_path '/saved_views/{id}' do
        operation :patch do
          key :tags, [
            'SavedViews'
          ]
          key :summary, 'Update a SavedView'
          key :description, 'Updates and returns a single SavedView'
          key :operationId, 'update_saved_view_path'
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of SavedView to update'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :saved_view
            key :in, :body
            key :description, 'SavedView object'
            key :required, true
            schema do
              key :'$ref', :SavedViewInput
            end
          end
          response 200 do
            key :description, 'Successful update of SavedView object'
            schema do
              key :title, 'SavedView'
              key :'$ref', :SavedView
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('access SavedView')
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def update
        if @saved_view.update(saved_view_params)
          render :show, status: :ok
        else
          render json: { errors: @saved_view.errors }, status: :unprocessable_entity
        end
      end

      swagger_path '/saved_views/{id}' do
        operation :delete do
          key :tags, [
            'SavedViews'
          ]
          key :summary, 'Destroy a SavedView'
          key :description, 'Destroys a single SavedView'
          key :operationId, 'destroy_saved_view_path'
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of SavedView to destroy'
            key :required, true
            key :type, :string
          end
          response 204 do
            key :description, 'Successful SavedView deletion'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('access SavedView')
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          extend SwaggerResponses::ValidationFailureResponse
        end
      end

      def destroy
        @saved_view.destroy
        head :no_content
      end

      private

      def set_saved_view
        @saved_view = SavedView.find(params[:id])
      end

      def saved_view_params
        params.require(:saved_view).permit(:id, :name, :path, :description)
      end

      def check_saved_view_permissions
        head :forbidden unless @saved_view.user_id == current_api_user.id
      end
    end
  end
end
