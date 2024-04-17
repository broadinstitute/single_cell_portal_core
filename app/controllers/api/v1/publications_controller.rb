module Api
  module V1
    class PublicationsController < ApiBaseController
      include Concerns::FireCloudStatus

      before_action :authenticate_api_user!
      before_action :set_study
      before_action :check_study_permission
      before_action :set_publication, except: [:index, :create]

      respond_to :json

      swagger_path '/studies/{accession}/publications' do
        operation :get do
          key :tags, [
              'Publications'
          ]
          key :summary, 'Find all Publications in a Study'
          key :description, 'Returns all Publications for the given Study'
          key :operationId, 'study_publications_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Array of Publication objects'
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'Publication'
                key :'$ref', :Publication
              end
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Publication')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      # GET /single_cell/api/v1/studies/:accession
      def index
        @publications = @study.publications
      end

      swagger_path '/studies/{accession}/publications/{id}' do
        operation :get do
          key :tags, [
              'Publications'
          ]
          key :summary, 'Find an Publication'
          key :description, 'Finds a single Publication'
          key :operationId, 'study_publication_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of Publication to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Publication object'
            schema do
              key :title, 'Publication'
              key :'$ref', :Publication
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, Publication)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      # GET /single_cell/api/v1/studies/:accession/publications/:id
      def show

      end

      swagger_path '/studies/{accession}/publications' do
        operation :post do
          key :tags, [
              'Publications'
          ]
          key :summary, 'Create an Publication'
          key :description, 'Creates and returns a single Publication'
          key :operationId, 'create_study_publication_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :publication
            key :in, :body
            key :description, 'Publication object'
            key :required, true
            schema do
              key :'$ref', :PublicationInput
            end
          end
          response 200 do
            key :description, 'Successful creation of Publication object'
            schema do
              key :title, 'Publication'
              key :'$ref', :Publication
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

      # POST /single_cell/api/v1/studies/:accession/publications
      def create
        @publication = @study.publications.build(publication_params)

        if @publication.save
          render :show
        else
          render json: {errors: @publication.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{accession}/publications/{id}' do
        operation :patch do
          key :tags, [
              'Publications'
          ]
          key :summary, 'Update an Publication'
          key :description, 'Updates and returns a single Publication.'
          key :operationId, 'update_study_publication_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of Publication to update'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :publication
            key :in, :body
            key :description, 'Publication object'
            key :required, true
            schema do
              key :'$ref', :PublicationInput
            end
          end
          response 200 do
            key :description, 'Successful update of Publication object'
            schema do
              key :title, 'Publication'
              key :'$ref', :Publication
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, Publication)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          extend SwaggerResponses::ValidationFailureResponse
        end
      end

      # PATCH /single_cell/api/v1/studies/:accession/publications/:id
      def update
        sanitized_update_params = publication_params.to_unsafe_hash.keep_if {|k,v| !v.blank?}
        if @publication.update(sanitized_update_params)
          render :show
        else
          render json: {errors: @publication.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{accession}/publications/{id}' do
        operation :delete do
          key :tags, [
              'Publications'
          ]
          key :summary, 'Delete an Publication'
          key :description, 'Deletes a single Publication'
          key :operationId, 'delete_study_publication_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of Publication to delete'
            key :required, true
            key :type, :string
          end
          response 204 do
            key :description, 'Successful Publication deletion'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('delete Publication')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, Publication)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      # DELETE /single_cell/api/v1/studies/:accession/publications/:id
      def destroy
        begin
          @publication.destroy
          head 204
        rescue => e
          ErrorTracker.report_exception(e, current_api_user, @publication, params)
          MetricsService.report_error(e, request, current_api_user, @study)
          render json: {error: e.message}, status: 500
        end
      end

      private

      def set_study
        study_key = params[:study_id]
        if study_key.start_with?('SCP')
          @study = Study.find_by(accession: study_key)
        else
          @study = Study.find_by(id: study_key)
        end
        if @study.nil? || @study.queued_for_deletion?
          head 404 and return
        end
      end

      def set_publication
        @publication = Publication.find_by(id: params[:id])
        if @publication.nil?
          head 404 and return
        end
      end

      def check_study_permission
        head 403 unless @study.can_edit?(current_api_user)
      end

      # study file params list
      def publication_params
        params.require(:publication).permit(:id, :accession, :title, :journal, :url, :pmcid, :citation, :preprint)
      end
    end
  end
end

