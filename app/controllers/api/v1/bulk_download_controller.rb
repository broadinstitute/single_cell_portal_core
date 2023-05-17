module Api
  module V1
    class BulkDownloadController < ApiBaseController
      before_action :authenticate_api_user!

      DEFAULT_BULK_FILE_TYPES = [
        'Cluster', 'Metadata', 'Expression Matrix', 'MM Coordinate Matrix', '10X Genes File', '10X Barcodes File'
      ].freeze

      swagger_path '/bulk_download/auth_code' do
        operation :post do
          key :tags, [
              'Bulk Download'
          ]
          key :summary, 'Create one-time auth code for downloads'
          key :description, 'Create and return a one-time authorization code (OTAC) to identify a user for bulk downloads'
          key :operationId, 'bulk_download_auth_code_path'
          parameter do
            key :name, :bulk_download
            key :type, :object
            key :in, :body
            schema do
              property :file_ids do
                key :type, :string
                key :description, 'Comma-delimited list of StudyFile IDs (such as returned from the summary endpoint)'
                key :required, true
                key :example, "6269614d94ec8f18bd30f94a,6269614e94ec8f18bd30f94b,6269614f94ec8f18bd30f94c"
              end
              property :tdr_files do
                key :type, :object
                key :description, 'Hash of file arrays to download from TDR, keyed by accession. Each file should specify name, file_type, and project_id'
                key :required, true
                key :example, "{ HCAProjectName: [{'project_id': 'a39728aa-70a0-4201-b0a2-81b7badf3e71', " \
                              "'name': 'HCAProjectName.tsv', 'file_type': 'Project Manifest', 'count': 1}, " \
                              "{'project_id': 'a39728aa-70a0-4201-b0a2-81b7badf3e71', 'file_format': 'loom', " \
                              "'file_type': 'analysis_file', 'count': 2}]}"
              end
            end
          end
          response 200 do
            key :description, 'One-time auth code and time interval, in seconds'
            schema do
              property :auth_code do
                key :type, :integer
                key :description, 'One-time auth code'
              end
              property :time_interval do
                key :type, :integer
                key :description, 'Time interval (in seconds) OTAC will be valid'
              end
              property :download_id do
                key :type, :string
                key :description, 'ID that can be passed to generate_curl_config in lieu of file_ids'
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

      def auth_code
        half_hour = 1800 # seconds

        totat = current_api_user.create_totat(half_hour, api_v1_bulk_download_generate_curl_config_path)

        # discard any empty Azul entries - this can happen if row is selected, but no file types are checked
        if bulk_download_params[:azul_files].present?
          valid_azul_files = bulk_download_params.to_unsafe_hash[:azul_files].reject { |_, files| files.empty? }
        end

        # do a pre-emptive check against user's download quota to see if this request will exceed the limit
        # if so, render an appropriate message as executing the download will result in an incomprehensible error
        # like - Warning: cfg.txt:1: warning: '{"error"' is unknown ; curl: no URL specified!
        requested_files = self.class.load_study_files(ids: bulk_download_params[:file_ids])
        requested_bytes = ::BulkDownloadService.get_requested_bytes(requested_files)
        if ::DownloadQuotaService.download_exceeds_quota?(current_api_user, requested_bytes)
          error_msg = "This download will exceed your daily quota.  #{::DownloadQuotaService::QUOTA_HELP_EMAIL}"
          render json: { error: error_msg }, status: :failed_dependency and return
        end

        auth_download = DownloadRequest.create!(
          auth_code: totat[:totat],
          file_ids: bulk_download_params[:file_ids],
          azul_files: valid_azul_files,
          user_id: current_api_user.id
        )


        auth_code_response = {
          auth_code: totat[:totat],
          time_interval: totat[:totat_info][:valid_seconds],
          download_id: auth_download.id.to_s
        }
        render json: auth_code_response
      end

      swagger_path '/bulk_download/summary' do
        operation :get do
          key :tags, [
              'Bulk Download'
          ]
          key :summary, 'Summary information of studies requested for download'
          key :description, 'Preview of the names, number of files and bytes (by file type) requested for download from search results'
          key :operationId, 'search_bulk_download_summary_path'
          parameter do
            key :name, :accessions
            key :type, :string
            key :in, :query
            key :description, 'Comma-delimited list of Study accessions'
            key :required, true
          end
          response 200 do
            key :description, 'Information about total number of files and sizes by type'
            key :type, :object
            key :title, 'FileSizesByType'
            schema do
              StudyFile::BULK_DOWNLOAD_TYPES.each do |file_type|
                property file_type do
                  key :type, :object
                  key :title, file_type
                  key :description, "#{file_type} files"
                  property :total_files do
                    key :type, :integer
                    key :description, "Number of #{file_type} files"
                  end
                  property :total_bytes do
                    key :type, :integer
                    key :description, "Total number of bytes for #{file_type} files"
                  end
                end
              end
            end
          end
          response 400 do
            key :description, 'Invalid study accessions or requested file types'
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def summary
        # sanitize study accessions
        valid_accessions = self.class.find_matching_accessions(params[:accessions])
        # extract HCA project names from accession list, if present
        hca_accessions = self.class.extract_hca_accessions(params[:accessions])
        begin
          # only validate accessions, if present.  TDR/HCA-only downloads will not have SCP accessions present
          self.class.check_accession_permissions(valid_accessions, current_api_user) if valid_accessions.any?
        rescue ArgumentError => e
          # there's a good argument that this should return a 403 rather than 422 when there are studies requested that the user
          # does not have access to.  However, our current default handling of 401/403 errors in the UX makes that undesirable
          # once SCP-4010 is addressed, this can be restored to 403.
          # The response uses JSON API formatting -- details: https://jsonapi.org/format/#error-objects
          render json: { errors: [{status: 422, detail: e.message, title: 'Invalid studies requested' }] }, status: 422 and return
        end

        @study_file_info = ::BulkDownloadService.get_download_info(valid_accessions)
        hca_file_info = ::AzulSearchService.get_file_summary_info(hca_accessions)
        @study_file_info += hca_file_info if hca_file_info.any?

        render json: @study_file_info
      end

      swagger_path '/bulk_download/drs_info' do
        operation :post do
          key :tags, [
            'Bulk Download'
          ]
          key :summary, 'Retrieve information about DRS file objects in TDR'
          key :description, 'Retrieve file-level information about DRS objects existing in Terra Data Repo, such as filenames, sizes, and access URLs.'
          key :operationId, 'search_bulk_download_drs_info'
          parameter do
            key :name, :drs_ids
            key :type, :array
            key :in, :body
            key :description, 'Array of DRS IDs'
            key :example, "{\"drs_ids\":[\"drs://jade.datarepo-dev.broadinstitute.org/v1_257c5646-689a-4f25-8396-2500c849cb4f_8f63e624-5e41-44fa-aabe-5133ec12c4bc\"]}"
            key :required, true
          end
          response 200 do
            key :type, :array
            key :description, 'Array of file information objects, containing filenames, sizes, and access URLs.  See ' \
                              'https://jade.datarepo-dev.broadinstitute.org/swagger-ui.html#/DataRepositoryService/getObject ' \
                              'for more information regarding response structure.'
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 500 do
            key :description, 'Invalid DRS ID format'
          end
        end
      end

      def drs_info
        drs_ids = params[:drs_ids]
        file_info = Parallel.map(drs_ids, in_threads: 100) do |drs_id|
          begin
            ApplicationController.data_repo_client.get_drs_file_info(drs_id)
          rescue RestClient::Exception => e
            # DataRepoClient only emits RestClient::Exception errors, and the error will have already been reported
            # to Sentry, so also report to Mixpanel
            MetricsService.report_error(e, request, current_api_user)
            {
              drs_id: drs_id,
              error: e.message
            }
          end
        end
        render json: file_info
      end

      swagger_path '/bulk_download/generate_curl_config' do
        operation :get do
          key :tags, [
              'Bulk Download'
          ]
          key :summary, 'Get curl command file for bulk file download'
          key :description, 'Generates a curl config file for downloading files in bulk of multiple types. Specify either study accessions and types, or file IDs, or a download ID'
          key :operationId, 'bulk_download_generate_curl_config_path'
          parameter do
            key :name, :auth_code
            key :type, :integer
            key :in, :query
            key :description, 'User-specific one-time authorization code'
            key :required, true
          end
          parameter do
            key :name, :accessions
            key :type, :string
            key :in, :query
            key :description, 'Comma-delimited list of Study accessions'
            key :required, true
          end
          parameter do
            key :name, :file_types
            key :in, :query
            key :description, 'Comma-delimited list of file types'
            key :required, false
            key :type, :array
            items do
              key :type, :string
              key :enum, StudyFile::BULK_DOWNLOAD_TYPES
            end
            key :collectionFormat, :csv
          end
          parameter do
            key :name, :file_ids
            key :in, :query
            key :description, 'Comma-delimited list of file ids'
            key :required, false
            key :type, :array
            items do
              key :type, :string
            end
            key :collectionFormat, :csv
          end
          parameter do
            key :name, :download_id
            key :in, :query
            key :description, 'a DownloadRequest ID, such as returned by a call to the auth_code endpoint'
            key :required, false
            key :type, :string
          end
          parameter do
            key :name, :directory
            key :type, :string
            key :in, :query
            key :description, 'Name of directory folder to download (for single-study bulk download only), can be "all"'
            key :required, false
          end
          parameter do
            key :name, :context
            key :type, :string
            key :in, :query
            key :description, 'Context of the download, its scope: either "study" or "global"'
            key :required, false
          end
          response 200 do
            key :description, 'Curl configuration file with signed URLs for requested data'
            key :type, :string
          end
          response 400 do
            key :description, 'Invalid study accessions or requested file types'
          end
          response 401 do
            key :description, ApiBaseController.unauthorized
          end
          response 403 do
            key :description, ApiBaseController.forbidden('download with provided auth_token, or download exceeds user quota')
            schema do
              key :title, 'Error'
              property :message do
                key :type, :string
                key :description, 'Error message'
              end
            end
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def generate_curl_config
        valid_accessions = []
        file_ids = []
        azul_files = {}

        # determine if this a single-study bulk download (from download tab) or from home page search
        search_context = params[:context] || 'unknown'

        # determine what format we need for output paths based on client OS
        browser = Browser.new(request.env['HTTP_USER_AGENT'])
        os = browser&.platform&.name || 'Mac OS X'

        # branch based on whether they provided a download_id, file_ids, or accessions
        if params[:download_id]
          download_req = DownloadRequest.find(params[:download_id])
          render json: { error: 'Invalid download_id provided' }, status: 400 and return if download_req.blank?

          azul_files = download_req.azul_files_as_hash
          file_ids = download_req.file_ids
        elsif params[:file_ids]
          begin
            file_ids = RequestUtils.validate_id_list(params[:file_ids])
          rescue ArgumentError
            render json: { error: 'file_ids must be comma-delimited list of 24-character UUIDs' }, status: 400 and return
          end
        else
          valid_accessions = self.class.find_matching_accessions(params[:accessions])
          sanitized_file_types = self.class.find_matching_file_types(params[:file_types], accessions: valid_accessions)
        end

        # if they provided file_ids (either directly or via download_id), get the corresponding studies
        if file_ids.any?
          matched_study_ids = StudyFile.where(:id.in => file_ids).pluck(:study_id)
          valid_accessions = Study.where(:id.in => matched_study_ids).pluck(:accession)
        end

        begin
          # only validate accessions if set either in POST body or DownloadRequest object
          # if user is only downloading TDR/HCA data, then no SCP accessions will have been set
          self.class.check_accession_permissions(valid_accessions, current_api_user) if valid_accessions.any?
        rescue ArgumentError => e
          render json: e.message, status: 403 and return
        end

        # if this is a single-study download, allow for DirectoryListing downloads
        if valid_accessions.size == 1 && params[:directory].present?
          study_accession = valid_accessions.first
          directory_name, file_type = params[:directory].split('--')
          directories = self.class.find_matching_directories(directory_name, file_type, study_accession)
          directory_files = ::BulkDownloadService.get_requested_directory_files(directories)
        else
          directories = []
          directory_files = []
        end

        # get requested files, depending on access method
        files_requested = self.class.load_study_files(ids: file_ids, accessions: valid_accessions, file_types: sanitized_file_types)

        # determine quota impact & update user's download quota
        # will throw a RuntimeError if the download exceeds the user's daily quota
        begin
          ::BulkDownloadService.update_user_download_quota(user: current_api_user, files: files_requested, directories: directories)
        rescue RuntimeError => e
          render json: { error: e.message }, status: 403 and return
        end

        # create maps to avoid Mongo timeouts when generating curl commands in parallel processes
        bucket_map = ::BulkDownloadService.generate_study_bucket_map(valid_accessions) if valid_accessions.any?
        if files_requested.any? || directories.any?
          pathname_map = ::BulkDownloadService.generate_output_path_map(files_requested, directories, os: os)
        end

        # generate curl config file
        logger.info "Beginning creation of curl configuration for user_id, auth token: #{current_api_user.id}"
        start_time = Time.zone.now
        @configuration = ::BulkDownloadService.generate_curl_configuration(study_files: files_requested,
                                                                           directory_files: directory_files,
                                                                           user: current_api_user,
                                                                           study_bucket_map: bucket_map,
                                                                           output_pathname_map: pathname_map,
                                                                           azul_files: azul_files,
                                                                           context: search_context,
                                                                           os: os)
        end_time = Time.zone.now
        runtime = TimeDifference.between(start_time, end_time).humanize
        logger.info "Curl configs generated for studies #{valid_accessions}, #{files_requested.size + directory_files.size} total files"
        logger.info "Total time in generating curl configuration: #{runtime}"
        send_data @configuration, type: 'text/plain', filename: 'cfg.txt'
      end

      def self.check_accession_permissions(valid_accessions, user)
        if valid_accessions.blank?
          raise ArgumentError, 'Invalid request parameters; study accessions not found'
        end
        accessions_by_permission = ::BulkDownloadService.get_permitted_accessions(study_accessions: valid_accessions,
                                                                                  user: user)
        if accessions_by_permission[:forbidden].any? || accessions_by_permission[:lacks_acceptance].any?
          error_msg = "Forbidden: cannot access one or more requested studies for download.\n "
          if accessions_by_permission[:forbidden].any?
            error_msg += "You do not have permission to view #{accessions_by_permission[:forbidden].join(', ')}"
          end
          if accessions_by_permission[:lacks_acceptance].any?
            error_msg += "Download agreement required for #{accessions_by_permission[:lacks_acceptance].join(', ')}. \n\n"
            error_msg += 'Visit the "Download" tab at these URL(s) and accept the agreement to enable download:\n'
            error_msg += accessions_by_permission[:lacks_acceptance].map do |accession|
              RequestUtils.get_base_url + Rails.application.routes.url_helpers.view_study_path(accession: accession, study_name: '')
            end.join(' \n')
          end
          raise ArgumentError, error_msg
        end
      end

      # find valid StudyAccessions from query parameters
      # only returns accessions currently in use that are not detached and have no workspace
      def self.find_matching_accessions(raw_accessions)
        accessions = RequestUtils.split_query_param_on_delim(parameter: raw_accessions)
        sanitized_accessions = StudyAccession.sanitize_accessions(accessions)
        Study.where(detached: false, :accession.in => sanitized_accessions).pluck(:accession)
      end

      # extract out HCA "accessions" (project shortnames) by filtering out SCP accessions
      def self.extract_hca_accessions(raw_accessions)
        accessions = RequestUtils.split_query_param_on_delim(parameter: raw_accessions)
        accessions.reject { |accession| accession =~ StudyAccession::ACCESSION_FORMAT }
      end

      # find valid bulk download types from query parameters
      def self.find_matching_file_types(raw_file_types, accessions:)
        file_types = RequestUtils.split_query_param_on_delim(parameter: raw_file_types)
        if file_types.count > 0
          return StudyFile::BULK_DOWNLOAD_TYPES & file_types # find array intersection
        end
        # default is return all types
        # if this is a single-study bulk download w/o file types, return all file types present in that study
        if accessions.size == 1
          study = Study.find_by(accession: accessions.first)
          study.study_files.pluck(:file_type).uniq
        else
          DEFAULT_BULK_FILE_TYPES
        end
      end

      # find matching directories in a given study
      # this only works for single-study bulk download, not from advanced/faceted search
      # can be 'all', or a single directory (with specified file_type as well)
      def self.find_matching_directories(directory_name, file_type, accession)
        study = Study.find_by(accession: accession)
        sanitized_dirname = CGI.unescape(directory_name)
        case sanitized_dirname.downcase
        when 'nodirs'
          []
        when 'all'
          study.directory_listings.all
        else
          DirectoryListing.where(name: sanitized_dirname, study_id: study.id, sync_status: true, file_type: file_type)
        end
      end

      # find matching study files, either directly by id, or via a list of accessions and file types
      # ignore detached studies to avoid issues downloading
      def self.load_study_files(ids: [], accessions: [], file_types: [])
        if ids.any?
          detached = Study.where(detached: true).pluck(:id)
          StudyFile.where(:id.in => ids, :study_id.nin => detached)
        elsif accessions.any? && file_types.any?
          ::BulkDownloadService.get_requested_files(file_types: file_types, study_accessions: accessions)
        else
          # fallback case, return empty array to prevent downstream errors
          []
        end
      end

      private

      def bulk_download_params
        params.require(:bulk_download).permit(file_ids: [], azul_files: {})
      end
    end
  end
end
