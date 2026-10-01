module Api
  module V1
    module Concerns
      module ReadOnlyMode
        extend ActiveSupport::Concern

        def check_read_only_mode!
          if read_only_mode?
            render json: { error: "The portal is currently in read-only mode, meaning all study updates are blocked.  We apologize for any inconvenience." }, status: :forbidden and return
          end
        end

        def read_only_mode?
          if api_user_signed_in?
            current_api_user.feature_flag_for('read_only_mode')
          else
            feature_flag = FeatureFlag.find_by(name: 'read_only_mode')
            feature_flag&.default_value || false
          end
        end
      end
    end
  end
end