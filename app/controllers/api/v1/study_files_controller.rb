module Api
  module V1
    class StudyFilesController < ApiBaseController
      include Concerns::FireCloudStatus

      before_action :authenticate_api_user!
      before_action :set_study
      before_action :check_study_edit_permission
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
        begin
          new_id = params['study_file']['_id']
          # if an id is specified, and is not in use, use it
          if new_id
            if StudyFile.find(new_id).present?
              raise 'Duplicate ID -- please refresh the page and retry'
            end
            @study_file = StudyFile.new(study: @study, _id: RequestUtils.validate_mongo_id(new_id))
          else
            @study_file = StudyFile.new(study: @study)
          end
          perform_update!(@study_file)
          MetricsService.log('file-create', format_log_props('success', nil), current_api_user)
          render :show
        rescue Mongoid::Errors::Validations => e
          MetricsService.log('file-create', format_log_props('failure', e.summary), current_api_user)
          render json: {error: e.summary}, status: :unprocessable_entity
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
        begin
          perform_update!(@study_file)
          MetricsService.log('file-update', format_log_props('success', nil), current_api_user)
          render :show
        rescue Mongoid::Errors::Validations => e
          MetricsService.log('file-update', format_log_props('failure', e.summary), current_api_user)
          render json: {error: e.summary}, status: :unprocessable_entity
        end
      end

      def format_log_props(status, error_message)
        log_props = study_file_params.to_unsafe_hash
        # do not send the actual file to the log
        log_props.delete(:upload)
        # don't log file paths that may contain sensitive data
        log_props.delete(:remote_location)
        {
          studyAccession: @study.accession,
          error: error_message,
          params: log_props,
          status: status
        }
      end

      # update the given study file with the request params and save it
      # raises ArgumentError if the save fails due to model validations
      # if the save is successful and includes a complete upload, will send it to Terra
      # and kick off a parse job if requested
      def perform_update!(study_file)
        study = study_file.study
        if study_file_params[:file_type] == 'AnnData'
          study_file.build_ann_data_file_info if study_file.ann_data_file_info.blank?

          safe_file_params = study_file.ann_data_file_info.merge_form_data(study_file_params.to_unsafe_hash)
        else
          safe_file_params = study_file_params
        end

        is_chunked = false
        content_range = RequestUtils.parse_content_range_header(request.headers)
        if content_range.present?
          is_chunked = true
          if content_range[:first_byte] != 0
            raise ArgumentError, 'Beginning of file expected'
          end
          if content_range[:last_byte] == content_range[:total_size] - 1
            is_chunked = false # the chunk sent happens to be the entire file
          end
        end
        # Somewhere in Rails automagic, the upload filename is set as the study file name
        # We want to have it be the upload_file_name sent by the frontend
        if safe_file_params[:upload] && safe_file_params[:upload_file_name]
          safe_file_params[:upload].original_filename = safe_file_params[:upload_file_name]
        end
        if safe_file_params[:custom_color_updates]
          parsed_update = JSON.parse(safe_file_params[:custom_color_updates])
          safe_file_params['cluster_file_info'] = {custom_colors: ClusterFileInfo.merge_color_updates(study_file, parsed_update)}
          safe_file_params.delete(:custom_color_updates)
        end

        # manually check first if species/assembly was supplied by name
        species_name = safe_file_params[:species]
        safe_file_params.delete(:species)
        assembly_name = safe_file_params[:assembly]
        safe_file_params.delete(:assembly)
        set_taxon_and_assembly_by_name({species: species_name, assembly: assembly_name})
        # clear the id so that it doesn't get overwritten -- this would be a security hole for existing files
        # and for new files the id will have been set along with creation of the StudyFile object in the `create`
        # method above
        safe_file_params.delete(:_id)

        parse_on_upload = safe_file_params[:parse_on_upload]
        safe_file_params.delete(:parse_on_upload)

        # check if the name of the file has changed as we won't be able to tell after we saved
        name_changed = study_file.persisted? && study_file.name != safe_file_params[:name]
        # log the name properties to help with understanding SCP-4159
        MetricsService.log('file-update', {
          studyAccession: study.accession,
          message: 'name info',
          uploadFilename: safe_file_params[:upload_file_name],
          originalFilename: safe_file_params[:upload]&.original_filename,
          fileName: safe_file_params[:name],
          fileId: study_file._id.to_s,
          fileType: study_file.file_type,
          fileSize: study_file.upload_file_size
        }, current_api_user)

        study_file.update!(safe_file_params)

        # invalidate caches first
        study_file.delay.invalidate_cache_by_file_type

        # if a gene list or cluster got updated, we need to update the associated records
        if study_file.file_type == 'Gene List' && name_changed
          precomputed_entry = PrecomputedScore.find_by(study_file: study_file)
          if precomputed_entry.present?
            logger.info "Updating gene list #{precomputed_entry.name} to match #{study_file[:name]}"
            precomputed_entry.update(name: study_file.name)
          end
        elsif study_file.file_type == 'Cluster' && name_changed
          cluster = ClusterGroup.find_by(study_file: study_file)
          if cluster.present?
            logger.info "Updating cluster #{cluster.name} to match #{study_file.name}"
            # before updating, check if the defaults also need to change
            if study.default_cluster == cluster
              study.default_options[:cluster] = study_file.name
              study.save
            end
            cluster.update(name: study_file.name)
          end
        end

        if ['Expression Matrix', 'MM Coordinate Matrix'].include?(study_file.file_type) && !safe_file_params[:y_axis_label].blank?
          # if user is supplying an expression axis label, update default options hash
          options = study.default_options.dup
          options.merge!(expression_label: safe_file_params[:y_axis_label])
          study.update(default_options: options)
        end

        if safe_file_params[:upload].present? && !is_chunked
          complete_upload_process(study_file, parse_on_upload)
        end
      end


      # handles adding an additional chunk to a file upload.  Note that create/update must be
      # called first with the first chunk of the file, in order to initialize the process
      # if this is the last chunk, it will handle sending to firecloud and launching a
      # parse job if requested
      def chunk
        safe_file_params = study_file_params
        upload = safe_file_params[:upload]
        content_range = RequestUtils.parse_content_range_header(request.headers)
        if content_range.present?
          if content_range[:first_byte] == 0
            render json: {errors: 'create/update should be used for uploading the first chunk'}, status: :bad_request and return
          end
          if content_range[:first_byte] != @study_file.upload_file_size
            render json: {errors: "Incorrect chunk sent: expected bytes starting with #{@study_file.upload_file_size}, received #{content_range[:first_byte]}" }, status: :bad_request and return
          end
        else
          render json: {errors: 'Missing Content-Range header'}, status: :bad_request and return
        end

        File.open(@study_file.upload.path, "ab") do |f|
          f.write upload.read
        end

        # Update the upload_file_size attribute
        @study_file.upload_file_size = @study_file.upload_file_size.nil? ? upload.size : @study_file.upload_file_size + upload.size
        @study_file.save!

        if @study_file.upload_file_size >= content_range[:total_size]
          # this was the last chunk
          complete_upload_process(@study_file, safe_file_params[:parse_on_upload])
        end
        render :show
      end

      def complete_upload_process(study_file, parse_on_upload)
        study_file.update!(status: 'uploaded', parse_status: 'unparsed') # set status to uploaded on full create
        if parse_on_upload
          if study_file.parseable?
            FileParseService.run_parse_job(@study_file, @study, current_api_user)
          else
            # make sure we bundle non-parseable files if appropriate
            FileParseService.create_bundle_from_file_options(study_file, @study)
            @study.delay.send_to_firecloud(study_file) # send data to FireCloud if upload was performed
          end
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
            present = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, @study.bucket_id, @study_file.upload_file_name)
            if present
              ApplicationController.firecloud_client.execute_gcloud_method(:delete_workspace_file, 0, @study.bucket_id, @study_file.upload_file_name)
            end
          end
          head 204
        rescue => e
          ErrorTracker.report_exception(e, current_api_user, @study_file, params)
          MetricsService.report_error(e, request, current_api_user, @study)
          logger.error "Error in deleting #{@study_file.upload_file_name} from workspace: #{@study.firecloud_workspace}; #{e.message}"
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

      def set_study_file
        # get the study file and confirm that it is part of the given study
        @study_file = StudyFile.find_by(id: params[:id], study_id: @study)
        if @study_file.nil? || @study_file.queued_for_deletion?
          head 404 and return
        end
      end

      def check_study_permission
        head 403 unless @study.can_edit?(current_api_user)
      end

      # study file params list
      def study_file_params
        params.require(:study_file).permit(
          :_id, :taxon_id, :genome_assembly_id, :study_file_bundle_id, :name, :upload, :upload_file_name,
          :upload_content_type, :upload_file_size, :remote_location, :description, :is_spatial, :file_type, :status,
          :human_fastq_url, :human_data, :use_metadata_convention, :cluster_type, :generation, :x_axis_label,
          :y_axis_label, :z_axis_label, :x_axis_min, :x_axis_max, :y_axis_min, :y_axis_max, :z_axis_min, :z_axis_max,
          :species, :assembly, :external_link_url, :external_link_title, :external_link_description, :parse_on_upload,
          :custom_color_updates, :reference_anndata_file,
          spatial_cluster_associations: [],
          options: [
            :cluster_group_id, :font_family, :font_size, :font_color, :matrix_id, :submission_id, :bam_id,
            :analysis_name, :visualization_name, :cluster_name, :annotation_name, :cluster_file_id
          ],
          expression_file_info_attributes: [
            :_id, :_destroy, :library_preparation_protocol, :units, :biosample_input_type, :modality, :is_raw_counts,
            raw_counts_associations: []
          ],
          heatmap_file_info_attributes: [:id, :_destroy, :custom_scaling, :color_min, :color_max, :legend_label],
          cluster_form_info_attributes: [
            :_id, :name, :obsm_key_name, :description, :x_axis_label, :y_axis_label, :x_axis_min, :x_axis_max,
            :y_axis_min, :y_axis_max, :z_axis_min, :z_axis_max, spatial_cluster_associations: []
          ],
          metadata_form_info_attributes: [:_id, :use_metadata_convention, :description],
          extra_expression_form_info_attributes: [:_id, :taxon_id, :description, :y_axis_label],
          ann_data_file_info_attributes: [
            :_id, :reference_file, :has_clusters, :has_metadata, :has_expression, :has_raw_counts,
            data_fragments: AnnDataFileInfo::DATA_FRAGMENT_PARAMS
          ]
        )
      end
    end
  end
end
