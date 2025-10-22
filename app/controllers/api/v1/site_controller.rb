module Api
  module V1
    class SiteController < ApiBaseController
      before_action :set_current_api_user!
      before_action :authenticate_api_user!, only: [:download_data, :stream_data, :submit_differential_expression]
      before_action :set_study, except: [:studies, :check_terra_tos_acceptance, :renew_user_access_token]
      before_action :check_study_detached, only: [:download_data, :stream_data, :renew_read_only_access_token]
      before_action :check_study_view_permission, except: [:studies, :check_terra_tos_acceptance, :renew_user_access_token]
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
    end
  end
end
