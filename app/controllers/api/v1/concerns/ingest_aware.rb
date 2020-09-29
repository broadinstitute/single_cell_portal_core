module Api
  module V1
    module Concerns
      module IngestAware
        extend ActiveSupport::Concern
        INGEST_IMAGE_NAME = 'scp-ingest-pipeline'
        MANAGE_STUDY_NAME = 'single-cell-portal'
        SCP_PACKAGES = [INGEST_IMAGE_NAME, MANAGE_STUDY_NAME]

        included do
          before_action :validate_scp_user_agent!
        end

        # deny connections that declare they are from the single-cell-portal PyPI package and are using a
        # version of scp-ingest-pipeline that is not the current major release
        #
        # Examples:
        # 'User-Agent': 'single-cell-portal/0.1.3rc1 (manage-study) scp-ingest-pipeline/1.5.6 (ingest_pipeline.py)'
        # If the configured version of scp-ingest-pipeline is... (the response will be)
        #  * 0.x = the request is denied with 400: Bad Request
        #  * 1.x = the request is allowed to proceed
        #  * 2.x = the request is denied with 400: Bad Request
        #  * scp-ingest-pipeline-development:ddee8f5 (untagged dev image) = request is denied since tags to not match
        #
        # All other requests without UA headers, or non SCP-specific UA headers are allowed
        def validate_scp_user_agent!
          scp_package_headers = extract_scp_user_agent_headers(request)
          if scp_package_headers.any?
            # log usage to Mixpanel
            mixpanel_log_props = {
                user_agent: request.headers['User-Agent'],
                appFullPath: request.fullpath
            }
            if api_user_signed_in?
              MetricsService.merge_identities_in_mixpanel(current_api_user)
              MetricsService.log('manage-study', mixpanel_log_props, current_api_user)
            end
            ingest_image_attributes = AdminConfiguration.get_ingest_docker_image_attributes
            ingest_pipeline_version = ingest_image_attributes[:tag]
            request_ingest_version = scp_package_headers[INGEST_IMAGE_NAME]
            if ingest_pipeline_version.include?('.') && request_ingest_version.include?('.')
              # both server & client are using a tagged release of scp-ingest-pipeline, so only compare major versions
              # otherwise fall back to checking entire tag for non-production releases
              ingest_pipeline_version = ingest_pipeline_version.split('.').first.try(:to_i)
              request_ingest_version = request_ingest_version.split('.').first.try(:to_i)
            end
            if ingest_pipeline_version != request_ingest_version
              install_msg = format_pip_command(ingest_pipeline_version, request_ingest_version)
              render json: {error: "scp-ingest-pipeline: #{scp_package_headers[INGEST_IMAGE_NAME]} incompatible with host, " + \
                                 "please update via #{install_msg}"},
                     status: 400 and return
            end
          end
        end

        def extract_scp_user_agent_headers(request)
          agent = request.headers['User-Agent']
          scp_ua_headers = {}
          if agent.present?
            SCP_PACKAGES.each do |package|
              package_match = agent.match(/#{package}\/(\w|\.)+/)
              scp_ua_headers[package] = package_match.to_s.split('/').last if package_match
            end
          end
          scp_ua_headers
        end

        private

        # format a pip install command for users to install the correct version of the single-cell-portal package
        def format_pip_command(server_version, request_version)
          installed_version = AdminConfiguration.get_ingest_docker_image_attributes[:tag]
          pip_command = "\"pip install "
          if !installed_version.include?('.')
            # we are running against a development build, so no pip command will work
            # notify user of commit SHA and instruct them to point at this locally
            # this will only ever happen to SCP team members, never on production
            pip_command = "pointing your local installation of #{INGEST_IMAGE_NAME} at commit SHA '#{installed_version}'"
          else
            if server_version > request_version
              pip_command += "#{INGEST_IMAGE_NAME} --upgrade\""
            else
              pip_command += "'#{INGEST_IMAGE_NAME}==#{installed_version}' --force-reinstall\""
            end
          end
          pip_command
        end
      end
    end
  end
end
