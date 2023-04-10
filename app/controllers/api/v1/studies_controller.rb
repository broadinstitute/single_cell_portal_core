module Api
  module V1
    class StudiesController < ApiBaseController
      include Concerns::FireCloudStatus

      def firecloud_independent_methods
        # add file_info is essentially a more extensive 'show' method
        [:index, :show, :file_info]
      end

      before_action :set_study_id_param
      before_action :authenticate_api_user!
      before_action :set_study, except: [:index, :create]
      before_action :check_study_detached, except: [:index, :create]
      before_action :check_study_edit_permission, except: [:index, :create, :generate_manifest]
      before_action :check_study_view_permission, only: [:generate_manifest]

      respond_to :json

      SUPPORTED_LABEL_FONTS = ['Helvetica Neue', 'Arial', 'Times New Roman', 'Courier New', 'Verdana', 'Georgia', 'Trebuchet MS', 'Impact']

      swagger_path '/studies' do
        operation :get do
          key :tags, [
              'Studies'
          ]
          key :summary, 'Find all Studies'
          key :description, 'Returns all Studies editable by the current user'
          key :operationId, 'studies_path'
          response 200 do
            key :description, 'Array of Study objects'
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'Study'
                key :'$ref', :Study
              end
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      # GET /single_cell/api/v1/studies
      def index
        @studies = Study.accessible(current_api_user)
        study_owner_ids = @studies.pluck(:id, :user_id)
        user_info = User.where(:id.in => study_owner_ids.map{ |plucked_arr| plucked_arr[1] }).pluck(:id, :email)
        # create a hash of study_id => owner email
        @study_owner_emails = study_owner_ids.reduce({}) do |hash, study_owner_id|
          hash[study_owner_id[0].to_s] = user_info.find { |user| user[0] == study_owner_id[1] }[1]
          hash
        end

      end

      swagger_path '/studies/{id}' do
        operation :get do
          key :tags, [
              'Studies'
          ]
          key :summary, 'Find a Study'
          key :description, 'Finds a single Study'
          key :operationId, 'study_path'
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of Study to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Study object'
            schema do
              key :title, 'Study'
              key :'$ref', :Study
            end
          end

          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          extend SwaggerResponses::StudyControllerResponses
        end
      end

      # GET /single_cell/api/v1/studies/:id
      def show
      end

      def usage_stats
        usage_stats_params = {
          page_views: {
            event: 'page:view:site-study',
            type: 'unique',
            where_string: "properties[\"studyAccession\"] == \"#{@study.accession}\""
          },
          file_downloads: {
            event: 'click:link',
            type: 'general',
            where_string: "properties[\"studyAccession\"] == \"#{@study.accession}\" and properties[\"text\"] == \"file-download:study-single\""
          },
          bulk_downloads: {
            event: 'file-download:curl-config',
            type: 'general',
            where_string: "\"#{@study.accession}\" in properties[\"studyAccessions\"]"
          }
        }
        responses = Parallel.map(usage_stats_params.keys) do |key|
          response = MixpanelClient.fetch_segmentation_query(usage_stats_params[key][:event],usage_stats_params[key][:type], usage_stats_params[key][:where_string] )
        end
        usage_stats = {}
        usage_stats_params.keys.each_with_index do |key, index|
          usage_stats[key] = responses[index]
        end

        render json: usage_stats
      end

      # return JSON of the study, all study file objects, and any options values needed for the upload wizard
      # also includes feature flags, with study flags taking precedence over user flags
      swagger_path '/studies/{id}/file_info' do
        operation :get do
          key :tags, [
            'Studies'
          ]
          key :summary, 'Get Study info'
          key :description, 'Gets attribute, file, feature flag, and configuration information about a single Study'
          key :operationId, 'study_file_info_path'
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of Study to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            schema do
              property :study do
                key :description, 'Study object'
                key :title, 'Study'
                key :'$ref', :Study
              end
              property :files do
                key :type, :array
                key :title, 'Array<StudyFile>'
                items do
                  key :'$ref', :StudyFile
                end
              end
              property :feature_flags do
                key :type, :object
                key :title, 'FeatureFlagOptions'
                key :description, 'Hash of FeatureFlagOption values with defaults, e.g. flag_name => flag_value'
              end
              property :menu_options do
                key :type, :object
                key :title, 'MenuOptions'
                key :description, 'Hash of select menu options for various views'
                property :fonts do
                  key :type, :array
                  items do
                    key :type, :string
                  end
                end
                property :species do
                  key :type, :array
                  items do
                    key :type, :object
                    key :title, 'Species information'
                    property :id do
                      key :type, :string
                    end
                    property :common_name do
                      key :type, :string
                    end
                  end
                end
                property :units do
                  key :type, :array
                  items do
                    key :type, :string
                    key :enum, ExpressionFileInfo::UNITS_VALUES
                  end
                end
                property :library_preparation_protocol do
                  key :type, :array
                  items do
                    key :type, :string
                    key :enum, ExpressionFileInfo::LIBRARY_PREPARATION_VALUES
                  end
                end
                property :modality do
                  key :type, :array
                  items do
                    key :type, :string
                    key :enum, ExpressionFileInfo::MODALITY_VALUES
                  end
                end
                property :biosample_input_type do
                  key :type, :array
                  items do
                    key :type, :string
                    key :enum, ExpressionFileInfo::BIOSAMPLE_INPUT_TYPE_VALUES
                  end
                end
                property :sequence_file_types do
                  key :type, :array
                  items do
                    key :type, :string
                    key :enum, %w[Fastq BAM]
                  end
                end
                property :genome_assemblies do
                  key :type, :array
                  items do
                    key :type, :object
                    key :title, 'GenomeAssembly'
                    property :id do
                      key :type, :string
                    end
                    property :name do
                      key :type, :string
                    end
                    # show ID of associated parent Taxon for storing belongs_to association
                    property :taxon_id do
                      key :type, :string
                    end
                  end
                end
              end
            end
          end

          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          extend SwaggerResponses::StudyControllerResponses
        end
      end

      def file_info
        files_obj = []
        @study.study_files.where(queued_for_deletion: false).each do |study_file|
          file_hash = study_file.attributes
          file_hash[:is_complete] = study_file.should_bundle? ? study_file.has_completed_bundle? : true
          files_obj << file_hash
        end
        response_obj = {
          study: @study.attributes,
          files: files_obj,
          feature_flags: FeatureFlaggable.feature_flags_for_instances(current_api_user, @study)
        }
        if params[:include_options]
          response_obj[:menu_options] = {
            fonts: SUPPORTED_LABEL_FONTS,
            species: ActiveRecordUtils.pluck_to_hash(Taxon.sorted, [:id, :common_name])
              .map { |k| k[:id] = k[:id].to_s; k }, # return the hash but with ids converted to strings
            units: ExpressionFileInfo::UNITS_VALUES,
            library_preparation_protocol: ExpressionFileInfo::LIBRARY_PREPARATION_VALUES,
            modality: ExpressionFileInfo::MODALITY_VALUES,
            biosample_input_type: ExpressionFileInfo::BIOSAMPLE_INPUT_TYPE_VALUES,
            sequence_file_types: ['Fastq', 'BAM'],
            genome_assemblies: ActiveRecordUtils.pluck_to_hash(GenomeAssembly, [:id, :name, :taxon_id])
              .map do |k| # return the hash but with ids converted to strings
                k[:id] = k[:id].to_s
                k[:taxon_id] = k[:taxon_id].to_s;
                k
              end
          }
        end
        render json: response_obj
      end

      swagger_path '/studies' do
        operation :post do
          key :tags, [
              'Studies'
          ]
          key :summary, 'Create a Study'
          key :description, 'Creates and returns a single Study'
          key :operationId, 'create_study_path'
          parameter do
            key :name, :study
            key :in, :body
            key :description, 'Study object'
            key :required, true
            schema do
              key :'$ref', :StudyInput
            end
          end
          response 200 do
            key :description, 'Successful creation of Study object'
            schema do
              key :title, 'Study'
              key :'$ref', :Study
            end
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          extend SwaggerResponses::StudyControllerResponses
          extend SwaggerResponses::ValidationFailureResponse
        end
      end

      # POST /single_cell/api/v1/studies
      def create
        @study = Study.new(study_params)
        @study.user = current_api_user # automatically set user from credentials


        if @study.save
          render :show
        else
          render json: {errors: @study.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{id}' do
        operation :patch do
          key :tags, [
              'Studies'
          ]
          key :summary, 'Update a Study'
          key :description, 'Updates and returns a single Study.  FireCloud project/workspace attributes cannot be changed.'
          key :operationId, 'update_study_path'
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of Study to update'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :study
            key :in, :body
            key :description, 'Study object'
            key :required, true
            schema do
              key :'$ref', :StudyUpdateInput
            end
          end
          response 200 do
            key :description, 'Successful update of Study object'
            schema do
              key :title, 'Study'
              key :'$ref', :Study
            end
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          extend SwaggerResponses::StudyControllerResponses
          extend SwaggerResponses::ValidationFailureResponse
        end
      end

      # PATCH /single_cell/api/v1/studies/:id
      def update
        if @study.update(study_params)
          if @study.previous_changes.keys.include?('name')
            # if user renames a study, invalidate all visualization caches and repopulate default cache
            CacheRemovalJob.new(@study.accession).perform
            ClusterCacheService.delay(queue: :cache).cache_study_defaults(@study)
          end
          render :show
        else
          render json: {errors: @study.errors}, status: :unprocessable_entity
        end
      end

      swagger_path '/studies/{id}' do
        operation :delete do
          key :tags, [
              'Studies'
          ]
          key :summary, 'Delete a Study'
          key :description, 'Deletes a single Study'
          key :operationId, 'delete_study_path'
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of Study to delete'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :workspace
            key :in, :query
            key :description, 'Keep FireCloud workspace after study deletion?'
            key :required, false
            key :type, :string
            key :enum, ['persist']
          end
          response 204 do
            key :description, 'Successful Study deletion'
          end
          extend SwaggerResponses::StudyControllerResponses
          response 403 do
            key :description, ApiBaseController.forbidden('delete Study')
          end
        end
      end

      # DELETE /single_cell/api/v1/studies/:id
      def destroy
        # check if user is allowed to delete study
        if @study.can_delete?(current_api_user)
          # set queued_for_deletion manually - gotcha due to race condition on page reloading and how quickly delayed_job can process jobs
          @study.update(queued_for_deletion: true)

          if params[:workspace] == 'persist'
            @study.update(firecloud_workspace: nil)
          else
            begin
              ApplicationController.firecloud_client.delete_workspace(@study.firecloud_project, @study.firecloud_workspace)
            rescue => e
              ErrorTracker.report_exception(e, current_api_user, @study, params.to_unsafe_hash)
              MetricsService.report_error(e, request, current_api_user, @study)
              logger.error "Unable to delete workspace: #{@study.firecloud_workspace}; #{e.message}"
              render json: {error: "Error deleting FireCloud workspace #{@study.firecloud_project}/#{@study.firecloud_workspace}: #{e.message}"}, status: 500
            end
          end

          # queue jobs to delete study caches & study itself
          CacheRemovalJob.new(@study.accession).delay(queue: :cache).perform
          DeleteQueueJob.new(@study).delay.perform

          # revoke all study_shares
          @study.study_shares.delete_all

          head 204
        else
          head 403
        end
      end

      swagger_path '/studies/{id}/sync' do
        operation :post do
          key :tags, [
              'Studies'
          ]
          key :summary, 'Sync a Study'
          key :description, 'Synchronize a single Study against its FireCloud workspace & GCS bucket'
          key :operationId, 'sync_study_path'
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of Study to sync'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'StudyShares, StudyFiles, and DirectoryListings'
            schema do
              key :title, 'JSON object of StudyShares, StudyFiles, and DirectoryListings'
              property :study_shares do
                key :type, :array
                key :title, 'StudyShare array'
                items do
                  key :title, 'StudyShare'
                  key :'$ref', :StudyShare
                end
              end
              property :study_files do
                key :type, :object
                key :title, 'JSON object of synced, unsynced, and orphaned StudyFiles'
                property :unsynced do
                  key :title, 'Unsynced StudyFile array'
                  key :type, :array
                  items do
                    key :title, 'StudyFile'
                    key :'$ref', :StudyFile
                  end
                end
                property :synced do
                  key :title, 'Synced StudyFile array'
                  key :type, :array
                  items do
                    key :title, 'StudyFile'
                    key :'$ref', :StudyFile
                  end
                end
                property :orphaned do
                  key :title, 'Orphaned StudyFile array'
                  key :type, :array
                  items do
                    key :title, 'StudyFile'
                    key :'$ref', :StudyFile
                  end
                end
              end
              property :directory_listings do
                key :type, :object
                key :title, 'JSON object of synced and unsynced DirectoryListings'
                property :unsynced do
                  key :type, :array
                  key :title, 'Unsynced DirectoryListing array'
                  items do
                    key :title, 'DirectoryListing'
                    key :'$ref', :DirectoryListing
                  end
                end
                property :synced do
                  key :type, :array
                  key :title, 'Synced DirectoryListing array'
                  items do
                    key :title, 'DirectoryListing'
                    key :'$ref', :DirectoryListing
                  end
                end
              end
            end
          end
          response 403 do
            key :description, ApiBaseController.forbidden('edit Study')
          end
          extend SwaggerResponses::StudyControllerResponses
          response 500 do
            key :description, 'Server error when attempting to synchronize FireCloud workspace or access GCS objects'
          end
        end
      end

      def sync_study
        @study_files = @study.study_files.available
        @study_files.each { |study_file| study_file.build_expression_file_info if study_file.expression_file_info.nil? }

        # first sync permissions if necessary
        begin
          @permissions_changed = StudySyncService.update_shares_from_acl(@study)
        rescue => e
          ErrorTracker.report_exception(e, current_user, @study, params)
          MetricsService.report_error(e, request, current_user, @study)
          logger.error "Error syncing ACLs in workspace bucket #{@study.firecloud_workspace} due to error: #{e.message}"
          redirect_to merge_default_redirect_params(studies_path, scpbr: params[:scpbr]),
                      alert: "We were unable to sync with your workspace bucket due to an error: #{view_context.simple_format(e.message)}.  #{SCP_SUPPORT_EMAIL}" and return
        end

        # begin determining sync status with study_files and primary or other data
        begin
          @unsynced_files = StudySyncService.process_all_remotes(@study)
        rescue => e
          ErrorTracker.report_exception(e, current_user, @study, params)
          MetricsService.report_error(e, request, current_user, @study)
          logger.error "#{Time.zone.now}: error syncing files in workspace bucket #{@study.firecloud_workspace} due to error: #{e.message}"
          redirect_to merge_default_redirect_params(studies_path, scpbr: params[:scpbr]),
                      alert: "We were unable to sync with your workspace bucket due to an error: #{view_context.simple_format(e.message)}.  #{SCP_SUPPORT_EMAIL}" and return
        end

        # refresh study state before continuing as new records may have been inserted
        @study.reload
        @synced_directories = @study.directory_listings.are_synced
        @unsynced_directories = @study.directory_listings.unsynced

        # split directories into primary data types and 'others'
        @unsynced_primary_data_dirs, @unsynced_other_dirs = StudySyncService.load_unsynced_directories(@study)

        # now determine if we have study_files that have been 'orphaned' (cannot find a corresponding bucket file)
        @orphaned_study_files = StudySyncService.find_orphaned_files(@study)
        @available_files = StudySyncService.set_available_files(@unsynced_files)
        @synced_study_files = StudySyncService.set_synced_files(@study, @orphaned_study_files)
      end

      swagger_path '/studies/{id}/manifest' do
        operation :post do
          key :tags, [
              'Studies'
          ]
          key :summary, 'Get a study manifest file'
          key :description, 'Return a file summarizing the study and each of the files within it'
          key :operationId, 'generate_manifest'
          parameter do
            key :name, :id
            key :in, :path
            key :description, 'ID of study to generate manifest'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :include_dirs
            key :in, :query
            key :description, 'Include directory listings in manifest'
            key :required, false
            key :type, :string
          end
          response 200 do
            key :description, 'Manifest file'
            schema do
              key :title, 'JSON object of study and study file'
              # Once file format is finalized, complete this documentation
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('View Study')
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
          response 500 do
            key :description, 'Server error when attempting to generate study manifest'
          end
        end
      end

      def generate_manifest
        include_dirs = params[:include_dirs] == 'true'
        manifest_obj = BulkDownloadService.generate_study_files_tsv(@study, include_dirs)
        response.headers['Content-Disposition'] = 'attachment; filename=file_supplemental_info.tsv'
        render plain: manifest_obj
      end

      private

      # copy the 'id' param to 'study_id' so that it can be compatible with StudyAware concern
      # note that renaming the parameter in routes.rb with 'param: study_id' would result in
      # nested routes getting that parameter as 'study_study_id'
      def set_study_id_param
        params[:study_id] = params[:id]
      end

      # study params list
      def study_params
        params.require(:study).permit(:name, :description, :public, :embargo, :use_existing_workspace, :firecloud_workspace,
                                      :firecloud_project, :cell_count, :gene_count, :view_order,  branding_group_ids: [],
                                      study_shares_attributes: [:id, :_destroy, :email, :permission],
                                      study_detail_attributes: [:id, :full_description],
                                      :default_options => [:cluster, :annotation, :color_profile, :expression_label, :deliver_emails,
                                                           :cluster_point_size, :cluster_point_alpha, :cluster_point_border],
                                      external_resources_attributes: [:id, :_destroy, :title, :description, :url, :publication_url],
                                      authors_attributes: [:id, :first_name, :last_name, :institution, :corresponding, :_destroy],
                                      publications_attributes: [:id, :title, :journal, :citation, :url, :pmcid, :preprint, :_destroy])
      end
    end
  end
end
