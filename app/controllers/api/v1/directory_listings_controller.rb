module Api
  module V1
    class DirectoryListingsController < ApiBaseController
      include Swagger::Blocks
      include Concerns::Authenticator

      before_action :authenticate_api_user!
      before_action :set_study
      before_action :check_study_permission
      before_action :set_directory_listing, except: [:index, :create]

      respond_to :json

      swagger_path '/studies/{study_id}/directory_listings' do
        operation :get do
          key :tags, [
              'DirectoryListings'
          ]
          key :summary, 'Find all DirectoryListings in a Study'
          key :description, 'Returns all DirectoryListings for the given Study'
          key :operationId, 'study_directory_listings_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Array of DirectoryListing objects'
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'DirectoryListing'
                key :'$ref', :DirectoryListing
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
        end
      end

      # GET /single_cell/api/v1/studies/:study_id/directory_listings
      def index
        @directory_listings = @study.directory_listings
      end

      swagger_path '/studies/{study_id}/directory_listings/{id}' do
        operation :get do
          key :tags, [
              'DirectoryListings'
          ]
          key :summary, 'Find a DirectoryListing'
          key :description, 'Finds a single Study'
          key :operationId, 'study_directory_listing_path'
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
            key :description, 'ID of DirectoryListing to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'DirectoryListing object'
            schema do
              key :title, 'DirectoryListing'
              key :'$ref', :DirectoryListing
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, DirectoryListing)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end
      
      # GET /single_cell/api/v1/studies/:study_id/directory_listings/:id
      def show
      end

      swagger_path '/studies/{study_id}/directory_listings' do
        operation :post do
          key :tags, [
              'DirectoryListings'
          ]
          key :summary, 'Create a DirectoryListing'
          key :description, 'Creates and returns a single DirectoryListing'
          key :operationId, 'create_study_directory_listing_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :directory_listing
            key :in, :body
            key :description, 'DirectoryListing object'
            key :required, true
            schema do
              key :'$ref', :DirectoryListingInput
            end
          end
          response 200 do
            key :description, 'Successful creation of DirectoryListing object'
            schema do
              key :title, 'DirectoryListing'
              key :'$ref', :DirectoryListing
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

      # POST /single_cell/api/v1/studies/:study_id/directory_listings
      def create
        @directory_listing = @study.directory_listings.build(directory_listing_params)

        if @directory_listing.save
          # set sync_status to true if directory saved, unless this was manually set
          set_sync_status
          render :show
        else
          render json: {errors: @directory_listing.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{study_id}/directory_listings/{id}' do
        operation :patch do
          key :tags, [
              'DirectoryListings'
          ]
          key :summary, 'Update a DirectoryListing'
          key :description, 'Updates and returns a single DirectoryListing'
          key :operationId, 'update_study_directory_listing_path'
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
            key :description, 'ID of DirectoryListing to update'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :directory_listing
            key :in, :body
            key :description, 'DirectoryListing object'
            key :required, true
            schema do
              key :'$ref', :DirectoryListingInput
            end
          end
          response 200 do
            key :description, 'Successful update of DirectoryListing object'
            schema do
              key :title, 'DirectoryListing'
              key :'$ref', :DirectoryListing
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, DirectoryListing)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          extend SwaggerResponses::ValidationFailureResponse
        end
      end

      # PATCH /single_cell/api/v1/studies/:study_id/directory_listings/:id
      def update
        if @directory_listing.update(directory_listing_params)
          # set sync_status to true if directory saved, unless this was manually set
          set_sync_status
          render :show
        else
          render json: {errors: @directory_listing.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{study_id}/directory_listings/{id}' do
        operation :delete do
          key :tags, [
              'DirectoryListings'
          ]
          key :summary, 'Delete a DirectoryListing'
          key :description, 'Deletes a single DirectoryListing'
          key :operationId, 'delete_study_directory_listing_path'
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
            key :description, 'ID of DirectoryListing to delete'
            key :required, true
            key :type, :string
          end
          response 204 do
            key :description, 'Successful DirectoryListing deletion'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, DirectoryListing)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      # DELETE /single_cell/api/v1/studies/:study_id/directory_listings/:id
      def destroy
        begin
          @directory_listing.destroy
          head 204
        rescue => e
          ErrorTracker.report_exception(e, current_api_user, params.to_unsafe_hash)
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

      def set_directory_listing
        @directory_listing = DirectoryListing.find_by(id: params[:id])
        if @directory_listing.nil?
          head 404 and return
        end
      end

      def check_study_permission
        head 403 unless @study.can_edit?(current_api_user)
      end

      # study file params whitelist
      def directory_listing_params
        params.require(:directory_listing).permit(:id, :name, :description, :file_type, :sync_status, files: [:name, :size, :generation])
      end

      # check sync_status on directory create/update, will default to true unless manually set to false
      def set_sync_status
        sync_status = ActiveModel::Type::Boolean.new.cast(directory_listing_params[:sync_status])
        if sync_status.nil?
          @directory_listing.update(sync_status: true)
        else
          @directory_listing.update(sync_status: sync_status)
        end
      end
    end
  end
end

