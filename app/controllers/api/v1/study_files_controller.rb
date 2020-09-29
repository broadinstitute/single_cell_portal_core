module Api
  module V1
    class StudyFilesController < ApiBaseController

      include Concerns::FireCloudStatus
      include Concerns::Authenticator
      include Swagger::Blocks

      before_action :authenticate_api_user!
      before_action :set_study
      before_action :check_study_permission
      before_action :set_study_file, except: [:index, :create, :bundle]

      respond_to :json

      swagger_path '/studies/{study_id}/study_files' do
        operation :get do
          key :tags, [
              'StudyFiles'
          ]
          key :summary, 'Find all StudyFiles in a Study'
          key :description, 'Returns all StudyFiles in a given Study'
          key :operationId, 'study_study_files_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Array of Study objects'
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'StudyFile'
                key :'$ref', :StudyFile
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
        @study_files = @study.study_files.where(queued_for_deletion: false)
      end

      swagger_path '/studies/{study_id}/study_files/{id}' do
        operation :get do
          key :tags, [
              'StudyFiles'
          ]
          key :summary, 'Find a StudyFile'
          key :description, 'Finds a single StudyFile'
          key :operationId, 'study_study_file_path'
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
            key :description, 'ID of StudyFile to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'StudyFile object'
            schema do
              key :title, 'StudyFile'
              key :'$ref', :StudyFile
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, StudyFile)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 410 do
            key :description, ApiBaseController.resource_gone
          end
        end
      end

      # GET /single_cell/api/v1/studies/:study_id/study_files/:id
      def show

      end

      swagger_path '/studies/{study_id}/study_files' do
        operation :post do
          key :tags, [
              'StudyFiles'
          ]
          key :summary, 'Create a StudyFile'
          key :description, 'Creates and returns a single StudyFile'
          key :operationId, 'create_study_study_file_path'
          key :consumes, ['multipart/form-data']
          key :produces, ['application/json']
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, 'study_file[file_type]'
            key :in, :formData
            key :required, true
            schema do
              key :type, :string
              key :enum, StudyFile::STUDY_FILE_TYPES
            end
          end
          parameter do
            key :name, 'study_file[name]'
            key :in, :formData
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, 'study_file[species]'
            key :description, '(optional) Common name of a species registered in the portal to set taxon_id association manually'
            key :type, :string
            key :in, :formData
          end
          parameter do
            key :name, 'study_file[assembly]'
            key :description, '(optional) Name of a genome assembly registered in the portal to set genome_assembly_id association manually'
            key :type, :string
            key :in, :formData
          end
          parameter do
            key :name, 'study_file[upload]'
            key :type, :file
            key :in, :formData
          end
          response 200 do
            key :description, 'Successful creation of StudyFile object'
            schema do
              key :title, 'StudyFile'
              key :'$ref', :StudyFile
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, StudyFile)
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

      # POST /single_cell/api/v1/studies/:study_id/study_files
      def create
        # since there is no species/assembly attribute for study_files, we need to prune that from study_file_params
        create_params = study_file_params.to_unsafe_hash
        # manually check first if species/assembly was supplied by name
        species_name = create_params[:species]
        create_params.delete(:species)
        assembly_name = create_params[:assembly]
        create_params.delete(:assembly)
        @study_file = @study.study_files.build(create_params)
        set_taxon_and_assembly_by_name({species: species_name, assembly: assembly_name})
        if @study_file.save
          # send data to FireCloud if upload was performed
          if study_file_params[:upload].present?
            @study.delay.send_to_firecloud(@study_file)
          end
          @study_file.update(status: 'uploaded') # set status to uploaded on full create
          render :show
        else
          render json: {errors: @study_file.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{study_id}/study_files/{id}' do
        operation :patch do
          key :tags, [
              'StudyFiles'
          ]
          key :summary, 'Update a StudyFile'
          key :description, 'Updates and returns a single StudyFile'
          key :operationId, 'update_study_study_file_path'
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
            key :description, 'ID of StudyFile to update'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :study_file
            key :in, :body
            key :description, 'StudyFile object'
            key :required, true
            schema do
              key :'$ref', :StudyFileInput
            end
          end
          response 200 do
            key :description, 'Successful update of Study object'
            schema do
              key :title, 'StudyFile'
              key :'$ref', :StudyFile
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, StudyFile)
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

      # PATCH /single_cell/api/v1/studies/:study_id/study_files/:id
      def update
        # since there is no species/assembly attribute for study_files, we need to prune that from study_file_params
        update_params = study_file_params.to_unsafe_hash
        # manually check first if species/assembly was supplied by name
        species_name = update_params[:species]
        update_params.delete(:species)
        assembly_name = update_params[:assembly]
        update_params.delete(:assembly)
        set_taxon_and_assembly_by_name({species: species_name, assembly: assembly_name})

        # check if the name of the file has changed as we won't be able to tell after we saved
        name_changed = @study_file.name != update_params[:name]

        if @study_file.update(update_params)
          # invalidate caches first
          @study_file.delay.invalidate_cache_by_file_type

          # send data to FireCloud if upload was performed
          if study_file_params[:upload].present?
            @study.delay.send_to_firecloud(@study_file)
            @study_file.update(status: 'uploaded') # set status to uploaded on full create
          end

          if ['Cluster', 'Coordinate Labels', 'Gene List'].include?(@study_file.file_type) && @study_file.valid?
            @study_file.invalidate_cache_by_file_type
          end
          # if a gene list or cluster got updated, we need to update the associated records
          if study_file_params[:file_type] == 'Gene List' && name_changed
            @precomputed_entry = PrecomputedScore.find_by(study_file_id: study_file_params[:_id])
            logger.info "Updating gene list #{@precomputed_entry.name} to match #{study_file_params[:name]}"
            @precomputed_entry.update(name: @study_file.name)
          elsif study_file_params[:file_type] == 'Cluster' && name_changed
            @cluster = ClusterGroup.find_by(study_file_id: study_file_params[:_id])
            logger.info "Updating cluster #{@cluster.name} to match #{study_file_params[:name]}"
            # before updating, check if the defaults also need to change
            if @study.default_cluster == @cluster
              @study.default_options[:cluster] = @study_file.name
              @study.save
            end
            @cluster.update(name: @study_file.name)
          elsif ['Expression Matrix', 'MM Coordinate Matrix'].include?(study_file_params[:file_type]) && !study_file_params[:y_axis_label].blank?
            # if user is supplying an expression axis label, update default options hash
            @study.update(default_options: @study.default_options.merge(expression_label: study_file_params[:y_axis_label]))
          end
          render :show
        else
          render json: {errors: @study_file.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{study_id}/study_files/{id}' do
        operation :delete do
          key :tags, [
              'StudyFiles'
          ]
          key :summary, 'Delete a StudyFile'
          key :description, 'Deletes a single StudyFile'
          key :operationId, 'delete_study_study_file_path'
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
            key :description, 'ID of StudyFile to delete'
            key :required, true
            key :type, :string
          end
          response 204 do
            key :description, 'Successful StudyFile deletion'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, StudyFile)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 410 do
            key :description, ApiBaseController.resource_gone
          end
          response 423 do
            key :description, ApiBaseController.resource_locked(StudyFile)
          end
        end
      end

      # DELETE /single_cell/api/v1/studies/:study_id/study_files/:id
      def destroy
        if !@study_file.can_delete_safely?
          render json: {error: 'Requested file is being used in active parse job'}, status: 423 and return
        end
        human_data = @study_file.human_data # store this reference for later
        # delete matching caches
        @study_file.invalidate_cache_by_file_type
        # queue for deletion
        @study_file.update(queued_for_deletion: true)
        DeleteQueueJob.new(@study_file).delay.perform
        begin
          # make sure file is in FireCloud first
          unless human_data || @study_file.generation.blank?
            present = Study.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, @study.bucket_id, @study_file.upload_file_name)
            if present
              Study.firecloud_client.execute_gcloud_method(:delete_workspace_file, 0, @study.bucket_id, @study_file.upload_file_name)
            end
          end
          head 204
        rescue => e
          error_context = ErrorTracker.format_extra_context(@study_file, {params: params})
          ErrorTracker.report_exception(e, current_api_user, error_context)
          logger.error "#{Time.zone.now}: error in deleting #{@study_file.upload_file_name} from workspace: #{@study.firecloud_workspace}; #{e.message}"
          render json: {error: "Error deleting remote file in bucket: #{e.message}"}, status: 500
        end
      end

      swagger_path '/studies/{study_id}/study_files/{id}/parse' do
        operation :post do
          key :tags, [
              'StudyFiles'
          ]
          key :summary, 'Parse a StudyFile'
          key :description, 'Parses a single StudyFile.  Will perform parse in a background process and email the requester upon completion'
          key :operationId, 'parse_study_study_file_path'
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
            key :description, 'ID of StudyFile to parse'
            key :required, true
            key :type, :string
          end
          response 204 do
            key :description, 'Successful StudyFile parse launch'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, StudyFile)
          end
          response 405 do
            key :description, 'StudyFile is already parsing'
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 410 do
            key :description, ApiBaseController.resource_gone
          end
          response 412 do
            key :description, 'StudyFile can only be parsed when bundled in a StudyFileBundle along with other required files, such as MM Coordinate Matrices and 10X Genes/Barcodes files'
          end
          response 422 do
            key :description, 'StudyFile is not parseable'
          end
        end
      end

      # POST /single_cell/api/v1/studies/:study_id/study_files/:id/parse
      def parse
        parse_response = FileParseService.run_parse_job(@study_file, @study, current_api_user)
        if parse_response[:status_code] == 204
          head 204
        else
          render json: parse_response, status: parse_response[:status_code]
        end
      end

      swagger_path '/studies/{study_id}/study_files/bundle' do
        operation :post do
          key :tags, [
              'StudyFiles'
          ]
          key :summary, 'Bundle multiple StudyFiles'
          key :description, "Create a StudyFileBundle to associate multiple StudyFiles of dependent types: ```#{StudyFileBundle.swagger_requirements.html_safe}```"
          key :operationId, 'bundle_study_study_file_path'
          parameter do
            key :name, :study_id
            key :in, :path
            key :description, 'ID of Study'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :files
            key :in, :body
            key :description, 'List of files to bundle together'
            key :required, true
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'StudyFile'
                key :'$ref', :FileBundleInput
              end
            end
          end
          response 200 do
            key :description, 'Successful StudyFileBundle creation'
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
            key :description, ApiBaseController.not_found(Study, StudyFile)
          end
          response 405 do
            key :description, 'StudyFile is already parsing'
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 410 do
            key :description, ApiBaseController.resource_gone
          end
          response 412 do
            key :description, 'StudyFile can only be parsed when bundled in a StudyFileBundle along with other required files, such as MM Coordinate Matrices and 10X Genes/Barcodes files'
          end
          response 422 do
            key :description, 'StudyFile is not parseable'
          end
        end
      end

      # POST /single_cell/api/v1/studies/:study_id/study_files/bundle
      # Create a StudyFileBundle from a list of files
      def bundle
        # must convert to an unsafe hash re: https://github.com/rails/rails/pull/28734
        unsafe_params = params.to_unsafe_hash
        file_params = unsafe_params[:files]
        if file_params.present?
          @study_file_bundle = StudyFileBundle.new(original_file_list: file_params, study_id: params[:study_id])
          if @study_file_bundle.save
            render 'api/v1/study_file_bundles/show'
          else
            render json: @study_file_bundle.errors, status: :unprocessable_entity
          end
        else
          render json: {error: "Malformed request: payload must be formatted as {files: [{name: 'filename', file_type: 'file_type'}]}"},
                 status: :bad_request
        end
      end

      private

      # manual check to see if user supplied taxon/assembly by name
      def set_taxon_and_assembly_by_name(param_list)
        species_name = param_list[:species]
        assembly_name = param_list[:assembly]
        matching_taxon = Taxon.find_by(common_name: /#{species_name}/i)
        matching_assembly = GenomeAssembly.find_by(name: /#{assembly_name}/i)
        if matching_taxon.present? && !species_name.blank?
          @study_file.taxon_id = matching_taxon.id
        end
        if matching_assembly.present? && !assembly_name.blank?
          @study_file.genome_assembly_id = matching_assembly.id
        end
      end

      def set_study
        @study = Study.find_by(id: params[:study_id])
        if @study.nil? || @study.queued_for_deletion?
          head 404 and return
        elsif @study.detached?
          head 410 and return
        end
      end

      def set_study_file
        @study_file = StudyFile.find_by(id: params[:id])
        if @study_file.nil? || @study_file.queued_for_deletion?
          head 404 and return
        end
      end

      def check_study_permission
        head 403 unless @study.can_edit?(current_api_user)
      end

      # study file params whitelist
      def study_file_params
        params.require(:study_file).permit(:_id, :study_id, :taxon_id, :genome_assembly_id, :study_file_bundle_id, :name,
                                           :upload, :upload_file_name, :upload_content_type, :upload_file_size, :remote_location,
                                           :description, :file_type, :status, :human_fastq_url, :human_data, :use_metadata_convention,
                                           :cluster_type, :generation, :x_axis_label, :y_axis_label, :z_axis_label, :x_axis_min,
                                           :x_axis_max, :y_axis_min, :y_axis_max, :z_axis_min, :z_axis_max, :species, :assembly,
                                           options: [:cluster_group_id, :font_family, :font_size, :font_color, :matrix_id,
                                                     :submission_id, :bam_id, :analysis_name, :visualization_name, :cluster_name,
                                                     :annotation_name])
      end
    end
  end
end
