module Api
  module V1
    module Concerns
      module FireCloudStatus
        extend ActiveSupport::Concern

        included do
          before_action :check_firecloud_status!, unless: proc {action_name == :index || action_name == :show}
        end

        # check on FireCloud API status and respond accordingly
        def check_firecloud_status!
          unless ApplicationController.firecloud_client.services_available?(FireCloudClient::SAM_SERVICE, FireCloudClient::RAWLS_SERVICE)
            alert = 'Study workspaces are temporarily unavailable, so we cannot complete your request.  Please try again later.'
            render json: {error: alert}, status: 503
          end
        end
      end
    end
  end
end
