module Api
  module V1
    class SiteController < ApiBaseController
      before_action :set_current_api_user!
      before_action :authenticate_api_user!, only: [:download_data, :stream_data, :submit_differential_expression,
                                                    :get_study_analysis_config, :submit_study_analysis, :get_study_submissions,
                                                    :get_study_submission, :sync_submission_outputs]
      before_action :set_study, except: [:studies, :check_terra_tos_acceptance, :analyses, :get_analysis, :renew_user_access_token]
      before_action :set_analysis_configuration, only: [:get_analysis, :get_study_analysis_config]
      before_action :check_study_detached, only: [:download_data, :stream_data, :get_study_analysis_config,
                                                  :submit_study_analysis, :get_study_submissions,
                                                  :get_study_submission, :sync_submission_outputs,
                                                  :renew_read_only_access_token]
      before_action :check_study_view_permission, except: [:studies, :check_terra_tos_acceptance, :analyses, :get_analysis, :renew_user_access_token]
      before_action :check_study_compute_permission,
                    only: [:get_study_analysis_config, :submit_study_analysis, :get_study_submissions,
                           :get_study_submission, :sync_submission_outputs]
      before_action :check_study_edit_permission, only: [:sync_submission_outputs]
      before_action :set_study_file, only: [:download_data, :stream_data]
      before_action :check_download_agreement, only: [:download_data, :stream_data]
      before_action :get_download_quota, only: [:download_data, :stream_data]

      swagger_path '/site/studies' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'Find all Studies viewable to user'
          key :description, 'Returns all Studies viewable by the current user, including public studies'
          key :operationId, 'site_studies_path'
          response 200 do
            key :description, 'Array of Study objects'
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'Study'
                key :'$ref', :SiteStudy
              end
            end
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def studies
        @studies = Study.viewable(current_api_user)
      end

      swagger_path '/site/check_terra_tos_acceptance' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'Check if user has accepted current Terra Terms of Service'
          key :description, 'Returns boolean for whether user has accepted current Terra ToS'
          key :operationId, 'site_check_terra_tos_acceptance_path'
          response 200 do
            key :description, 'Boolean for whether user has accepted current Terra ToS'
          end
          response 401 do
            key :description, 'Terra API rejected request due to user non-compliance with ToS'
          end
          response 404 do
            key :description, 'User account not found in Terra, does not need to accept ToS'
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 500 do
            key :description, 'Server error'
          end
        end
      end

      def check_terra_tos_acceptance
        if api_user_signed_in? && current_api_user.registered_for_firecloud
          user_status = current_api_user.check_terra_tos_status
          render json: { must_accept: user_status[:must_accept] }, status: user_status[:http_code]
        else
          render json: { must_accept: false }, status: :ok
        end
      end


      swagger_schema :DirectoryListingDownload do
        property :name do
          key :type, :string
          key :description, 'Name of remote Google Cloud Storage (GCS) directory containing files'
        end
        property :description do
          key :type, :string
          key :format, :email
          key :description, 'Block description for all files contained in DirectoryListing'
        end
        property :file_type do
          key :type, :string
          key :description, 'File type (i.e. extension) of all files contained in DirectoryListing'
        end
        property :download_url do
          key :type, :string
          key :description, 'URL to bulk download all files in this directory'
        end
        property :files do
          key :type, :array
          key :description, 'Array of file objects'
          items type: :object do
            key :title, 'GCS File object'
            key :required, [:name, :size, :generation]
            property :name do
              key :type, :string
              key :description, 'name of File'
            end
            property :size do
              key :type, :integer
              key :description, 'size of File'
            end
            property :generation do
              key :type, :string
              key :description, 'GCS generation tag of File'
            end
          end
        end
      end

      swagger_path '/site/studies/{accession}' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'View a Study & available StudyFiles'
          key :description, 'View a single Study, and any StudyFiles available for download/streaming, plus ExternalResource links'
          key :operationId, 'site_study_view_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Study, Array of StudyFiles, ExternalResources'
            schema do
              key :title, 'Study, StudyFiles'
              key :'$ref', :SiteStudyWithFiles
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      swagger_path '/site/studies/{accession}/renew_read_only_access_token' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'Renew a soon-expiring GCS access token for a study'
          key :description, 'Get a new 1-hour access token, within the authentication session duration'
          key :operationId, 'site_study_renew_read_only_access_token'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study to renew access for'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Access token for Google Cloud Storage'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def renew_read_only_access_token
        renewing_user = "an unauthenticated user (via read-only service account)"
        if current_api_user
          renewing_user = "user #{current_api_user.id}"
        end
        Rails.logger.info "Renewing read only access token via SCP API for #{renewing_user} in study #{@study.accession}"
        render json: RequestUtils.get_read_access_token(@study, current_api_user, renew: true)
      end


      swagger_path '/site/renew_user_access_token' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'Renew the user access token for a signed in user'
          key :description, 'Get a new access token'
          key :operationId, 'site_renew_user_access_token'
          response 200 do
            key :description, 'User access token for current signed in user'
          end
          response 204 do
            key :description, 'No user credentials supplied'
          end
          response 403 do
            key :description, ApiBaseController.forbidden('renew access token')
          end
          response 404 do
            key :description, ApiBaseController.not_found(User)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def renew_user_access_token
        if current_api_user
          Rails.logger.info "Renewing user access token via SCP API for #{current_api_user.id}"
          render json: RequestUtils.get_user_access_token(current_api_user)
        else
          Rails.logger.info "Cannot get a user access token for a user not signed in"
          head :no_content
        end
      end


      swagger_path '/site/studies/{accession}/download' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'Download a StudyFile'
          key :description, "Download a single StudyFile (via signed URL)<br/><br/><strong>NOTE</strong>: Due to CORS issues, files cannot be " + \
                            "downloaded via Swagger.  To download a file, either use a client such as Postman, or copy/paste " + \
                            "the CURL command into a terminal and add the '-L' flag immediately before the URL.".html_safe
          key :operationId, 'site_study_download_data_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study to fetch'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :filename
            key :in, :query
            key :description, 'Name/location of file to download'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'File object'
            key :type, :file
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view study')
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

      def download_data
        begin
          if @study_file.present?
            filesize = @study_file.upload_file_size
            if !DownloadQuotaService.download_exceeds_quota?(current_api_user, filesize)
              @signed_url = ApplicationController.firecloud_client.execute_gcloud_method(:generate_signed_url, 0, @study.bucket_id,
                                                                         @study_file.bucket_location, expires: 60)
              DownloadQuotaService.increment_user_quota(current_api_user, filesize)
              redirect_to @signed_url
            else
              alert = 'You have exceeded your current daily download quota.  You must wait until tomorrow to download this file.'
              render json: {error: alert}, status: 403
            end
          else
            render json: {error: "File not found: #{params[:filename]}"}, status: 404
          end
        rescue RuntimeError => e
          ErrorTracker.report_exception(e, current_api_user, @study, params.to_unsafe_hash)
          MetricsService.report_error(e, request, current_api_user, @study)
          logger.error "Error generating signed URL for #{params[:filename]}; #{e.message}"
          render json: {error: "Error generating signed URL for #{params[:filename]}; #{e.message}"}, status: 500
        end
      end

      swagger_path '/site/studies/{accession}/stream' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'Stream a StudyFile'
          key :description, 'Retrieve media URL for a StudyFile to stream to a client'
          key :operationId, 'site_study_stream_data_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study to fetch'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :filename
            key :in, :query
            key :description, 'Name/location of file to download'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'JSON object with media url'
            schema do
              key :type, :object
              key :title, 'File Details'
              property :filename do
                key :type, :string
                key :description, 'Name of file'
              end
              property :url do
                key :type, :string
                key :description, 'Media URL to stream requested file (requires Authorization Bearer token to access)'
              end
              property :access_token do
                key :type, :string
                key :description, 'Authorization bearer token to pass along with media URL request'
              end
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view study or stream file')
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

      def stream_data
        begin
          if @study_file.present?
            filesize = @study_file.upload_file_size
            if !DownloadQuotaService.download_exceeds_quota?(current_api_user, filesize)
              @media_url = @study_file.api_url
              DownloadQuotaService.increment_user_quota(current_api_user, filesize)
              # determine which token to return to use with the media url
              if @study.public?
                token = ApplicationController.read_only_firecloud_client.valid_access_token['access_token']
              elsif @study.has_bucket_access?(current_api_user)
                token = current_api_user.api_access_token
              else
                alert = 'You do not have permission to stream the requested file from the bucket'
                render json: {error: alert}, status: 403 and return
              end
              render json: {filename: params[:filename], url: @media_url, access_token: token}
            else
              alert = 'You have exceeded your current daily download quota.  You must wait until tomorrow to download this file.'
              render json: {error: alert}, status: 403
            end
          else
            render json: {error: "File not found: #{params[:filename]}"}, status: 404
          end
        rescue RuntimeError => e
          ErrorTracker.report_exception(e, current_api_user, @study, params.to_unsafe_hash)
          MetricsService.report_error(e, request, current_api_user, @study)
          logger.error "Error generating signed url for #{params[:filename]}; #{e.message}"
          render json: {error: "Error generating signed url for #{params[:filename]}; #{e.message}"}, status: 500
        end
      end

      swagger_path '/site/studies/{accession}/differential_expression' do
        operation :post do
          key :tags, [
            'Site'
          ]
          key :summary, 'Submit a differential expression calculation request'
          key :description, 'Request differential expression calculations for a given cluster/annotation in a study'
          key :operationId, 'site_study_submit_differential_expression_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study to use'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :de_job
            key :type, :object
            key :in, :body
            schema do
              property :cluster_name do
                key :description, 'Name of cluster group.  Use "_default" to use the default cluster'
                key :required, true
                key :type, :string
              end
              property :annotation_name do
                key :description, 'Name of annotation'
                key :required, true
                key :type, :string
              end
              property :annotation_scope do
                key :description, 'Scope of annotation.  One of "study" or "cluster".'
                key :type, :string
                key :required, true
                key :enum, Api::V1::Visualization::AnnotationsController::VALID_SCOPE_VALUES
              end
              property :de_type do
                key :description, 'Type of differential expression analysis. Either "rest" (one-vs-rest) or "pairwise"'
                key :type, :string
                key :required, true
                key :enum, %w[rest pairwise]
              end
              property :group1 do
                key :description, 'First group for pairwise analysis (optional)'
                key :type, :string
              end
              property :group2 do
                key :description, 'Second group for pairwise analysis (optional)'
                key :type, :string
              end
            end
          end
          response 204 do
            key :description, 'Job successfully submitted'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view study, study has author DE')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, 'Cluster', 'Annotation')
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 409 do
            key :description, "Results are processing or already exist"
          end
          response 410 do
            key :description, ApiBaseController.resource_gone
          end
          response 422 do
            key :description, "Job parameters failed validation"
          end
          response 429 do
            key :description, 'Weekly user quota exceeded'
          end
        end
      end

      def submit_differential_expression
        # disallow DE calculation requests for studies with author DE
        if @study.differential_expression_results.where(is_author_de: true).any?
          render json: {
            error: 'User requests are disabled for this study as it contains author-supplied differential expression results'
          }, status: 403 and return
        end

        # check user quota before proceeding
        if DifferentialExpressionService.job_exceeds_quota?(current_api_user)
          # minimal log props to help gauge overall user interest, as well as annotation/de types
          log_props = {
            studyAccession: @study.accession, annotationName: params[:annotation_name], de_type: params[:de_type]
          }
          MetricsService.log('quota-exceeded-de', log_props, current_api_user, request:)
          current_quota = DifferentialExpressionService.get_weekly_user_quota
          render json: { error: "You have exceeded your weekly quota of #{current_quota} requests" },
                 status: 429 and return
        end

        cluster_name = params[:cluster_name]
        cluster = cluster_name == '_default' ? @study.default_cluster : @study.cluster_groups.by_name(cluster_name)
        render json: { error: "Requested cluster #{cluster_name} not found" }, status: 404 and return if cluster.nil?

        annotation_name = params[:annotation_name]
        annotation_scope = params[:annotation_scope]
        de_type = params[:de_type]
        pairwise = de_type == 'pairwise'
        group1 = params[:group1]
        group2 = params[:group2]
        annotation = AnnotationVizService.get_selected_annotation(
          @study, cluster:, annot_name: annotation_name, annot_type: 'group', annot_scope: annotation_scope
        )
        render json: { error: 'No matching annotation found' }, status: 404 and return if annotation.nil?

        de_params = { annotation_name:, annotation_scope:, de_type:, group1:, group2: }

        # check if these results already exist
        # for pairwise, also check if requested comparisons exist
        result = DifferentialExpressionResult.find_by(
          study: @study, cluster_group: cluster, annotation_name:, annotation_scope:, is_author_de: false
        )
        if result && (!pairwise || (pairwise && result.has_pairwise_comparison?(group1, group2)))
          render json: { error: "Requested results already exist" }, status: 409 and return
        end

        begin
          submitted = DifferentialExpressionService.run_differential_expression_job(
            cluster, @study, current_api_user, **de_params
          )
          if submitted
            DifferentialExpressionService.increment_user_quota(current_api_user)
            head 204
          else
            # submitted: false here means that there is a matching running DE job
            render json: { error: "Requested results are processing - please check back later" }, status: 409
          end
        rescue ArgumentError => e
          # job parameters failed to validate
          render json: { error: e.message}, status: 422 and return
        end
      end

      swagger_path '/site/analyses' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'Find all available analysis configurations'
          key :description, 'Returns all available analyses configured in SCP'
          key :operationId, 'site_get_analyses_path'
          response 200 do
            key :description, 'Array of AnalysisConfigurations'
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'AnalysisConfigurationList'
                key :'$ref', :AnalysisConfigurationList
              end
            end
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def analyses
        @analyses = AnalysisConfiguration.all
      end

      swagger_path '/site/analyses/{namespace}/{name}/{snapshot}' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'Find an analysis configuration'
          key :description, 'Returns analysis configured in SCP with required inputs & default values'
          key :operationId, 'site_get_analysis_path'
          parameter do
            key :name, :namespace
            key :in, :path
            key :description, 'Namespace of AnalysisConfiguration to fetch'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :name
            key :in, :path
            key :description, 'Name of AnalysisConfiguration to fetch'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :snapshot
            key :in, :path
            key :description, 'Snapshot ID of AnalysisConfiguration to fetch'
            key :required, true
            key :type, :integer
          end
          response 200 do
            key :description, 'Analysis Configuration with input parameters & default values'
            schema do
              key :title, 'AnalysisConfiguration'
              key :'$ref', :AnalysisConfiguration
            end
          end
          response 404 do
            key :description, ApiBaseController.not_found(AnalysisConfiguration)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def get_analysis
        @analysis_configuration = AnalysisConfiguration.find_by(namespace: params[:namespace], name: params[:name], snapshot: params[:snapshot].to_i)
      end

      swagger_path '/site/studies/{accession}/analyses/{namespace}/{name}/{snapshot}' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'Get a study-specific analysis configuration'
          key :description, 'Returns analysis configured in for a specific study with available inputs'
          key :operationId, 'site_get_study_analysis_config_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study to fetch'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :namespace
            key :in, :path
            key :description, 'Namespace of AnalysisConfiguration to fetch'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :name
            key :in, :path
            key :description, 'Name of AnalysisConfiguration to fetch'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :snapshot
            key :in, :path
            key :description, 'Snapshot ID of AnalysisConfiguration to fetch'
            key :required, true
            key :type, :integer
          end
          response 200 do
            key :description, 'Analysis Configuration with study-specific options and default values'
            schema do
              key :title, 'Analysis, Submission Options'
              key :type, :object
              property :analysis do
                key :type, :object
                key :title, 'Analysis'
                property :namespace do
                  key :type, :string
                  key :description, 'Namespace of requested analysis'
                end
                property :name do
                  key :type, :string
                  key :description, 'Name of requested analysis'
                end
                property :snapshot do
                  key :type, :integer
                  key :description, 'Snapshot ID of requested analysis'
                end
                property :entity_type do
                  key :type, :string
                  key :description, 'FireCloud entity type of analysis (may not be present)'
                end
              end
              property :submission_inputs do
                key :type, :array
                key :title, 'Submission Input Options'
                items do
                  property :default_value do
                    key :description, 'Default value (if present)'
                    key :type, :string
                  end
                  property :render_for_user do
                    key :type, :boolean
                    key :description, 'Indication of whether or not to show input to users'
                  end
                  property :input_type do
                    key :type, :string
                    key :description, 'Type of form input for parameter'
                  end
                  property :options do
                    key :type, :array
                    key :title, 'Select Option'
                    key :description, 'Select options if available'
                    items do
                      property :display do
                        key :type, :string
                        key :descrption, 'Display value for select'
                      end
                      property :value do
                        key :type, :string
                        key :description, 'Option value for select'
                      end
                    end
                  end
                end
              end
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view or run computes in Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, AnalysisConfiguration)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def get_study_analysis_config
        @submission_options = {}
        @analysis_configuration.analysis_parameters.inputs.sort_by(&:config_param_name).each do |parameter|
          @submission_options[parameter.config_param_name] = {
              default_value: parameter.parameter_value,
              render_for_user: parameter.visible,
              input_type: parameter.input_type
          }
          if parameter.input_type == :select
            opts = parameter.options_by_association_method((parameter.study_scoped? || parameter.associated_model == 'Study') ? @study : nil)
            @submission_options[parameter.config_param_name][:options] = opts.map {|option| {display: option.first, value: option.last}}
          end
        end
      end

      swagger_path '/site/studies/{accession}/analyses/{namespace}/{name}/{snapshot}' do
        operation :post do
          key :tags, [
              'Site'
          ]
          key :summary, 'Submit an analysis'
          key :description, 'Submit an analysis to Cromwell'
          key :operationId, 'site_submit_study_analysis_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study in which to submit analysis'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :namespace
            key :in, :path
            key :description, 'Namespace of AnalysisConfiguration to use'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :name
            key :in, :path
            key :description, 'Name of AnalysisConfiguration to use'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :snapshot
            key :in, :path
            key :description, 'Snapshot ID of AnalysisConfiguration to use'
            key :required, true
            key :type, :integer
          end
          parameter do
            key :name, :submission_inputs
            key :in, :body
            key :description, 'Analysis submission inputs (from GET /site/studies/{accession}/analyses/{namespace}/{name}/{snapshot})'
            key :required, true
            key :type, :object
            key :default, JSON.pretty_generate({submission_inputs: {"call_name.parameter_1" => "\"value\"", "call_name.parameter_2" => "\"value\""}}).to_s
          end
          response 200 do
            key :description, 'Analysis submission information'
          end
          response 400 do
            key :description, 'Malformed submission parameters'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view or run computes in Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study, AnalysisConfiguration)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 500 do
            key :description, 'Internal server error (no submission)'
          end
        end
      end

      def submit_study_analysis
        begin
          # before creating submission, we need to make sure that the user is on the 'all-portal' user group list if it exists
          current_api_user.add_to_portal_user_group

          # load analysis configuration
          @analysis_configuration = AnalysisConfiguration.find_by(namespace: params[:namespace], name: params[:name],
                                                                  snapshot: params[:snapshot].to_i)
          submission_inputs = params[:submission_inputs]
          logger.info "Updating configuration for #{@analysis_configuration.configuration_identifier} to run #{@analysis_configuration.identifier} in #{@study.firecloud_project}/#{@study.firecloud_workspace}"
          submission_config = @analysis_configuration.apply_user_inputs(submission_inputs)
          # save configuration in workspace
          ApplicationController.firecloud_client.create_workspace_configuration(@study.firecloud_project, @study.firecloud_workspace, submission_config)

          # submission must be done as user, so create a client with current_user and submit
          # TODO: figure out better way to assign access token based on API vs. MVC app, and figure out how to set submitter correctly
          user_client = FireCloudClient.new(user: current_api_user, project: @study.firecloud_project)

          logger.info "Creating submission for #{@analysis_configuration.configuration_identifier} using configuration: #{submission_config['name']} in #{@study.firecloud_project}/#{@study.firecloud_workspace}"
          @submission = user_client.create_workspace_submission(@study.firecloud_project, @study.firecloud_workspace,
                                                           submission_config['namespace'], submission_config['name'],
                                                           submission_config['entityType'], submission_config['entityName'])
          AnalysisSubmission.create(submitter: current_api_user.email, study_id: @study.id, firecloud_project: @study.firecloud_project,
                                    submission_id: @submission['submissionId'], firecloud_workspace: @study.firecloud_workspace,
                                    analysis_name: @analysis_configuration.identifier, submitted_on: Time.zone.now, submitted_from_portal: true)
          render json: @submission.to_json
        rescue => e
          ErrorTracker.report_exception(e, current_api_user, @study, params.to_unsafe_hash)
          MetricsService.report_error(e, request, current_api_user, @study)
          logger.error "Unable to submit workflow #{@analysis_configuration.identifier} in #{@study.firecloud_workspace} due to: #{e.class.name}: #{e.message}"
          alert = "We were unable to submit your workflow due to an error: #{e.class.name}: #{e.message}"
          render json: {error: alert}, status: 500
        end

      end

      swagger_path '/site/studies/{accession}/submissions' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'View all analysis submissions in a Study'
          key :description, 'View all analysis submissions in a given study'
          key :operationId, 'site_get_study_submissions_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Array of analysis submissions'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view or run computes in Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def get_study_submissions
        @submissions = TerraAnalysisService.list_submissions(@study)
        render json: @submissions
      end

      swagger_path '/site/studies/{accession}/submissions/{submission_id}' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'View a single analysis submission in a Study'
          key :description, 'View a single analysis submission in a given study'
          key :operationId, 'site_get_study_submission_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study to fetch'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :submission_id
            key :in, :path
            key :description, 'ID of FireCloud submissions to fetch'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Analysis submission object w/ individual workflow statuses'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view or run computes in Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def get_study_submission
        @submission = ApplicationController.firecloud_client.get_workspace_submission(@study.firecloud_project, @study.firecloud_workspace,
                                                                      params[:submission_id])
        render json: @submission
      end

      swagger_path '/site/studies/{accession}/submissions/{submission_id}' do
        operation :delete do
          key :tags, [
              'Site'
          ]
          key :summary, 'Abort a single analysis submission in a Study'
          key :description, 'Abort a single analysis submission in a given study'
          key :operationId, 'site_abort_study_submission_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study to fetch'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :submission_id
            key :in, :path
            key :description, 'ID of FireCloud submission to abort'
            key :required, true
            key :type, :string
          end
          response 204 do
            key :description, 'Analysis submission successfully aborted'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view or run computes in Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 412 do
            key :description, 'Analysis submission has already completed running and cannot be aborted anymore'
          end
        end
      end

      def abort_study_submission
        if !submission_completed?(@study, params[:submission_id])
          begin
            ApplicationController.firecloud_client.abort_workspace_submission(@study.firecloud_project, @study.firecloud_workspace,
                                                              params[:submission_id])
            analysis_submission = AnalysisSubmission.find_by(submission_id: params[:submission_id])
            if analysis_submission.present?
              analysis_submission.update(status: 'Aborted', completed_on: Time.zone.now)
            end
            head 204
          rescue => e
            ErrorTracker.report_exception(e, current_api_user, @study, params.to_unsafe_hash)
            MetricsService.report_error(e, request, current_api_user, @study)
            logger.error "Unable to abort submission: #{params[:submission_id]} due to error: #{e.message}"
            render json: {error: "#{e.class.name}: #{e.message}"}, status: 500
          end
        else
          render json: {error: "Cannot abort a completed submission; #{params[:submission_id]} has already finished."}, status: 412
        end
      end

      swagger_path '/site/studies/{accession}/submissions/{submission_id}/remove' do
        operation :delete do
          key :tags, [
              'Site'
          ]
          key :summary, 'Delete an analysis submission bucket directory'
          key :description, 'Delete an single analysis submission workspace bucket directory.  Will only work for completed submissions'
          key :operationId, 'site_abort_study_submission_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study to fetch'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :submission_id
            key :in, :path
            key :description, 'ID of FireCloud submission from which to remove bucket submission directory'
            key :required, true
            key :type, :string
          end
          response 204 do
            key :description, 'Analysis submission bucket directory successfully deleted'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view or run computes in Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 412 do
            key :description, 'Analysis submission is still running; cannot remove bucket submission directory'
          end
        end
      end

      def delete_study_submission_dir
        if submission_completed?(@study, params[:submission_id])
          begin
            # first, add submission to list of 'deleted_submissions' in workspace attributes (will hide submission in list)
            workspace = ApplicationController.firecloud_client.get_workspace(@study.firecloud_project, @study.firecloud_workspace)
            ws_attributes = workspace['workspace']['attributes']
            if ws_attributes['deleted_submissions'].blank?
              ws_attributes['deleted_submissions'] = [params[:submission_id]]
            else
              ws_attributes['deleted_submissions']['items'] << params[:submission_id]
            end
            logger.info "Adding #{params[:submission_id]} to workspace delete_submissions attribute in #{@study.firecloud_workspace}"
            ApplicationController.firecloud_client.set_workspace_attributes(@study.firecloud_project, @study.firecloud_workspace, ws_attributes)
            logger.info "Deleting analysis metadata for #{params[:submission_id]} in #{@study.url_safe_name}"
            AnalysisMetadatum.where(submission_id: params[:submission_id]).delete
            logger.info "Queueing submission #{params[:submission]} deletion in #{@study.firecloud_workspace}"
            submission_files = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_files, 0, @study.firecloud_project, @study.firecloud_workspace, prefix: params[:submission_id])
            DeleteQueueJob.new(submission_files).perform
            head 204
          rescue => e
            ErrorTracker.report_exception(e, current_user, @study, params)
            MetricsService.report_error(e, request, current_api_user, @study)
            logger.error "Unable to remove submission #{params[:submission_id]} files from #{@study.firecloud_workspace} due to: #{e.class.name}: #{e.message}"
            render json: {error: "Unable to delete the outputs for #{params[:submission_id]} due to the following error: #{e.class.name}: #{e.message}"}, status: 500
          end
        else
          render json: {error: "Cannot remove bucket directory of a running submission; #{params[:submission_id]} has not yet completed"}, status: 412
        end
      end

      swagger_path '/site/studies/{accession}/submissions/{submission_id}/sync' do
        operation :get do
          key :tags, [
              'Site'
          ]
          key :summary, 'Sync outputs for a submission'
          key :description, 'Sync submission outputs for a given submission in a Study'
          key :operationId, 'site_sync_submission_outputs_path'
          parameter do
            key :name, :accession
            key :in, :path
            key :description, 'Accession of Study to fetch'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :submission_id
            key :in, :path
            key :description, 'ID of FireCloud submissions to sync'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'Array of StudyFiles from submission'
            key :title, 'Submission outputs object'
            key :type, :object
            schema do
              property :submission_outputs do
                key :type, :array
                key :title, 'Array of StudyFiles objects to be synced from submission'
                items do
                  key :title, 'StudyFile'
                  key :'$ref', :StudyFile
                end
              end
            end
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('view or run computes in Study')
          end
          response 404 do
            key :description, ApiBaseController.not_found(Study)
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def sync_submission_outputs
        @synced_study_files = @study.study_files.valid
        @synced_directories = @study.directory_listings.to_a
        @unsynced_files = []
        @orphaned_study_files = []
        @unsynced_primary_data_dirs = []
        @unsynced_other_dirs = []
        begin
          # indication of whether or not we have custom sync code to run, defaults to false
          @special_sync = false
          submission = ApplicationController.firecloud_client.get_workspace_submission(@study.firecloud_project, @study.firecloud_workspace,
                                                                       params[:submission_id])
          configuration = ApplicationController.firecloud_client.get_workspace_configuration(@study.firecloud_project, @study.firecloud_workspace,
                                                                             submission['methodConfigurationNamespace'],
                                                                             submission['methodConfigurationName'])
          # get method identifiers to load analysis_configuration object
          method_name = configuration['methodRepoMethod']['methodName']
          method_namespace = configuration['methodRepoMethod']['methodNamespace']
          method_snapshot = configuration['methodRepoMethod']['methodVersion']
          @analysis_configuration = AnalysisConfiguration.find_by(namespace: method_namespace, name: method_name, snapshot: method_snapshot)
          if @analysis_configuration.present?
            @special_sync = true
          end
          submission['workflows'].each do |workflow|
            workflow = ApplicationController.firecloud_client.get_workspace_submission_workflow(@study.firecloud_project, @study.firecloud_workspace,
                                                                                params[:submission_id], workflow['workflowId'])
            workflow['outputs'].each do |output_name, outputs|
              if outputs.is_a?(Array)
                outputs.each do |output_file|
                  file_location = output_file.gsub(/gs\:\/\/#{@study.bucket_id}\//, '')
                  # get google instance of file
                  remote_file = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, @study.bucket_id, file_location)
                  if remote_file.present?
                    process_workflow_output(output_name, output_file, remote_file, workflow, params[:submission_id], configuration)
                  else
                    alert_content = "We were unable to sync the outputs from submission #{params[:submission_id]}; one or more of
                             the declared output files have been deleted.  Please check the output directory before continuing."
                    render json: {error: alert_content}, status: 500
                  end
                end
              else
                file_location = outputs.gsub(/gs\:\/\/#{@study.bucket_id}\//, '')
                # get google instance of file
                remote_file = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, @study.bucket_id, file_location)
                if remote_file.present?
                  process_workflow_output(output_name, outputs, remote_file, workflow, params[:submission_id], configuration)
                else
                  alert_content = "We were unable to sync the outputs from submission #{params[:submission_id]}; one or more of
                             the declared output files have been deleted.  Please check the output directory before continuing."
                  render json: {error: alert_content}, status: 500
                end
              end
            end
            metadata = AnalysisMetadatum.find_by(study_id: @study.id, submission_id: params[:submission_id])
            if metadata.nil?
              metadata_attr = {
                  name: submission['methodConfigurationName'],
                  submitter: submission['submitter'],
                  submission_id: params[:submission_id],
                  study_id: @study.id,
                  version: '4.6.1'
              }
              begin
                AnalysisMetadatum.create(metadata_attr)
              rescue => e
                ErrorTracker.report_exception(e, current_api_user, @study, params.to_unsafe_hash, { analysis_metadata: metadata_attr})
                MetricsService.report_error(e, request, current_api_user, @study)
                logger.error "Unable to create analysis metadatum for #{params[:submission_id]}: #{e.class.name}:: #{e.message}"
              end
            end
          end
          @available_files = @unsynced_files.map {|f| {name: f.name, generation: f.generation, size: f.upload_file_size}}
        rescue => e
          ErrorTracker.report_exception(e, current_api_user, @study, params)
          MetricsService.report_error(e, request, current_api_user, @study)
          alert = "We were unable to sync the outputs from submission #{params[:submission_id]} due to the following error: #{e.class.name}: #{e.message}"
          render json: {error: alert}, status: 500
        end
      end

      private

      ##
      # Setters
      ##

      def set_study
        @study = Study.find_by(accession: params[:accession])
        if @study.nil? || @study.queued_for_deletion?
          head 404 and return
        end
      end

      def set_study_file
        @study_file = @study.study_files.detect {|file| file.upload_file_name == params[:filename] || file.bucket_location == params[:filename]}
      end

      def set_analysis_configuration
        @analysis_configuration = AnalysisConfiguration.find_by(namespace: params[:namespace], name: params[:name], snapshot: params[:snapshot].to_i)
      end

      ##
      # Permission checks
      ##

      def check_study_view_permission
        if !@study.public? && !api_user_signed_in?
          head 401
        else
          head 403 unless @study.public? || @study.can_view?(current_api_user)
        end
      end

      def check_study_edit_permission
        if !api_user_signed_in?
          head 401
        else
          head 403 unless @study.can_edit?(current_api_user)
        end
      end

      def check_study_compute_permission
        if !api_user_signed_in?
          head 401
        else
          head 403 unless @study.can_compute?(current_api_user)
        end
      end

      def check_study_detached
        if @study.detached?
          head 410 and return
        end
      end

      def check_download_agreement
        if @study.has_download_agreement? && !@study.download_agreement.user_accepted?(current_api_user)
          head 403 and return
        end
      end

      # retrieve the current download quota
      def get_download_quota
        config_entry = AdminConfiguration.find_by(config_type: 'Daily User Download Quota')
        if config_entry.nil? || config_entry.value_type != 'Numeric'
          # fallback in case entry cannot be found or is set to wrong type
          @download_quota = 2.terabytes
        else
          @download_quota = config_entry.convert_value_by_type
        end
      end

      def de_job_params
        params.require(:de_job).permit(:cluster_name, :annotation_name, :annotation_scope, :de_type, :group1, :group2)
      end

      # update AnalysisSubmissions when loading study analysis tab
      # will not backfill existing workflows to keep our submission history clean
      def update_analysis_submission(submission)
        analysis_submission = AnalysisSubmission.find_by(submission_id: submission['submissionId'])
        if analysis_submission.present?
          workflow_status = submission['workflowStatuses'].keys.first # this only works for single-workflow analyses
          analysis_submission.update(status: workflow_status)
          analysis_submission.delay.set_completed_on # run in background to avoid UI blocking
        end
      end

      # boolean check for submission completion
      def submission_completed?(study, submission_id)
        submission = ApplicationController.firecloud_client.get_workspace_submission(study.firecloud_project, study.firecloud_workspace,
                                                                     submission_id)
        last_workflow = submission['workflows'].sort_by {|w| w['statusLastChangedDate']}.last
        AnalysisSubmission::COMPLETION_STATUSES.include?(last_workflow['status'])
      end

      # process a submission output file based on behavior from the corresponding anaylsis_configuration
      def process_workflow_output(output_name, file_url, remote_gs_file, workflow, submission_id, submission_config)
        path_parts = file_url.split('/')
        basename = path_parts.last
        new_location = "outputs_#{@study.id}_#{submission_id}/#{basename}"
        # check if file has already been synced first
        # we can only do this by md5 hash as the filename and generation will be different
        existing_file = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, @study.bucket_id, new_location)
        unless existing_file.present? && existing_file.md5 == remote_gs_file.md5 && StudyFile.where(study_id: @study.id, upload_file_name: new_location).exists?
          # now copy the file to a new location for syncing, marking as default type of 'Analysis Output'
          new_file = remote_gs_file.copy new_location
          unsynced_output = StudyFile.new(study_id: @study.id, name: new_file.name, upload_file_name: new_file.name,
                                          upload_content_type: new_file.content_type, upload_file_size: new_file.size,
                                          generation: new_file.generation, remote_location: new_file.name,
                                          options: {submission_id: params[:submission_id]})
          # process output according to analysis_configuration output parameters and associations (if present)
          workflow_parts = output_name.split('.')
          call_name = workflow_parts.shift
          param_name = workflow_parts.join('.')
          if @special_sync # only process outputs from 'registered' analyses
            Rails.logger.info "Processing output #{output_name}:#{file_url} in #{params[:submission_id]}/#{workflow['workflowId']}"
            # find matching output analysis_parameter
            output_param = @analysis_configuration.analysis_parameters.outputs.detect {|param| param.parameter_name == param_name && param.call_name == call_name}
            # set declared file type
            unsynced_output.file_type = output_param.output_file_type
            # process any direct attribute assignments or associations
            output_param.analysis_output_associations.each do |association|
              unsynced_output = association.process_output_file(unsynced_output, submission_config, @study)
            end
          end
          @unsynced_files << unsynced_output
        end
      end
    end
  end
end
