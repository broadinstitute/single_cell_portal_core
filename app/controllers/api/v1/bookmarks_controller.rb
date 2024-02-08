module Api
  module V1
    # scaffold controller for CRUDing user saved views
    class BookmarksController < ApiBaseController
      before_action :authenticate_api_user!
      before_action :set_bookmark, only: %i[show update destroy]
      before_action :check_bookmark_permissions, only: %i[show update destroy]

      respond_to :json

      swagger_path '/bookmarks' do
        operation :get do
          key :tags, [
            'Bookmarks'
          ]
          key :summary, 'Get my Bookmarks'
          key :description, 'Returns all Bookmarks for the given User'
          key :operationId, 'bookmarks_path'
          response 200 do
            key :description, 'Array of Bookmarks objects'
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'Bookmark'
                key :'$ref', :Bookmark
              end
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view Bookmarks')
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def index
        @bookmarks = current_api_user.bookmarks
      end

      swagger_path '/bookmarks/{id}' do
        operation :get do
          key :tags, [
            'Bookmarks'
          ]
          key :summary, 'Find a Bookmark'
          key :description, 'Finds a single Bookmark for the given User'
          key :operationId, 'bookmark_path'
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of Bookmark to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Bookmark object'
            schema do
              key :title, 'Bookmark'
              key :'$ref', :Bookmark
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('access Bookmark')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Bookmark)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def show; end

      swagger_path '/bookmarks' do
        operation :post do
          key :tags, [
            'Bookmarks'
          ]
          key :summary, 'Create a Bookmark'
          key :description, 'Creates and returns a single Bookmark'
          key :operationId, 'create_bookmark_path'
          parameter do
            key :name, :bookmark
            key :in, :body
            key :description, 'Bookmark object'
            key :required, true
            schema do
              key :'$ref', :BookmarkInput
            end
          end
          response 200 do
            key :description, 'Successful creation of Bookmark object'
            schema do
              key :title, 'Bookmark'
              key :'$ref', :Bookmark
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
        @bookmark = Bookmark.new(bookmark_params)
        @bookmark.user = current_api_user

        if @bookmark.save
          render :show, status: :ok
        else
          render json: { errors: @bookmark.errors }, status: :unprocessable_entity
        end
      end

      swagger_path '/bookmarks/{id}' do
        operation :patch do
          key :tags, [
            'Bookmarks'
          ]
          key :summary, 'Update a Bookmark'
          key :description, 'Updates and returns a single Bookmark'
          key :operationId, 'update_bookmark_path'
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of Bookmark to update'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :bookmark
            key :in, :body
            key :description, 'Bookmark object'
            key :required, true
            schema do
              key :'$ref', :BookmarkInput
            end
          end
          response 200 do
            key :description, 'Successful update of Bookmark object'
            schema do
              key :title, 'Bookmark'
              key :'$ref', :Bookmark
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('access Bookmark')
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def update
        if @bookmark.update(bookmark_params)
          render :show, status: :ok
        else
          render json: { errors: @bookmark.errors }, status: :unprocessable_entity
        end
      end

      swagger_path '/bookmarks/{id}' do
        operation :delete do
          key :tags, [
            'Bookmarks'
          ]
          key :summary, 'Destroy a Bookmark'
          key :description, 'Destroys a single Bookmark'
          key :operationId, 'destroy_bookmark_path'
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of Bookmark to destroy'
            key :required, true
            key :type, :string
          end
          response 204 do
            key :description, 'Successful Bookmark deletion'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('access Bookmark')
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          extend SwaggerResponses::ValidationFailureResponse
        end
      end

      def destroy
        @bookmark.destroy
        head :no_content
      end

      private

      def set_bookmark
        @bookmark = Bookmark.find(params[:id])
      end

      def bookmark_params
        params.require(:bookmark).permit(:id, :name, :path, :description)
      end

      def check_bookmark_permissions
        head :forbidden unless @bookmark.user_id == current_api_user.id
      end
    end
  end
end
