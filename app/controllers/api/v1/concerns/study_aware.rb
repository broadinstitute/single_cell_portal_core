module Api
  module V1
    module Concerns
      module StudyAware
        extend ActiveSupport::Concern

        def set_study
          @study = Study.any_of({accession: params[:study_id]},{id: params[:study_id]}).first
          if @study.nil? || @study.queued_for_deletion?
            head 404
          end
        end

        def set_storage_client
          @storage_client = StorageService.load_client(study: @study)
        end

        def set_public_storage_client
          @public_storage_client = StorageService.load_client(study: @study, public_access: true)
        end

        ##
        # Permission checks
        ##
        def check_study_view_permission
          unless @study.public?
            # check for a reviewer_session cookie if reviewer access is enabled
            if !api_user_signed_in? && @study.reviewer_access.present?
              reviewer = @study.reviewer_access
              session_key = cookies.signed[reviewer.cookie_name]
              head 401 if reviewer.expired? || session_key.blank? || !reviewer.session_valid?(session_key)
            elsif !api_user_signed_in?
              head 401
            else
              head 403 unless @study.can_view?(current_api_user)
            end
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
            head 410
          end
        end
      end
    end
  end
end
