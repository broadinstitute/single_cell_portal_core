module Api
  module V1
    class CurrentUserController < ApiBaseController
      # collection of API methods related to the current user object.
      # for security reasons, the methods in this controller should be extremely tightly controlled

      before_action :authenticate_api_user!
      before_action :check_read_only_mode!, only: [:update]

      ALLOWABLE_UPDATE_FIELDS = ['feature_flags'].freeze
      # to ensure users can't arbitrarily change their own flags, restrict the list
      # as part of SCP-3621, faceted search is removed from the allow list, but this controller is being left in
      # place as future feature flags may support opt in/out
      ALLOWABLE_UPDATE_FEATURE_FLAGS = [].freeze


      # updates the current user object -- only allowed fields are able to be changed
      def update
        user = current_api_user

        updated_user = params[:current_user]
        # if there are any fields included that are not allowed to be updated, return error
        if (ALLOWABLE_UPDATE_FIELDS - updated_user.keys).present?
          error_msg = "Only permitted fields (#{ALLOWABLE_UPDATE_FIELDS.join(', ')}) may be updated"
          render(json: {error: error_msg}, status: 422) and return
        end

        begin
          new_flags = updated_user.try(:[], :feature_flags)
          if new_flags
            disallowed_keys = ALLOWABLE_UPDATE_FEATURE_FLAGS - new_flags.keys
            if disallowed_keys.present?
              error_msg = "Only permitted flags (#{ALLOWABLE_UPDATE_FEATURE_FLAGS.join(', ')}) may be updated"
              render(json: {error: error_msg}, status: 422) and return
            end
            merged_flags = user.feature_flags.merge(new_flags)
            user.update!(feature_flags: merged_flags)
          end
        rescue => e
          render(json: {error: e.message}, status: 422) and return
        end

        # just return the feature flags object, to avoid exposing sensitive user fields
        render json: { feature_flags: user.feature_flags }
      end
    end
  end
end
