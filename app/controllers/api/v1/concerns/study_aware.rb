module Api
  module V1
    module Concerns
      module StudyAware
        extend ActiveSupport::Concern

        def set_study
          @study = Study.find_by(accession: params[:study_id])
          if @study.nil? || @study.queued_for_deletion?
            head 404 and return
          end
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
      end
    end
  end
end
