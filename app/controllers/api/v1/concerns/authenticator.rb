module Api
  module V1
    module Concerns
      module Authenticator
        extend ActiveSupport::Concern
        include ActionController::Cookies
        include ActionController::RequestForgeryProtection

        OAUTH_V3_TOKEN_INFO = 'https://www.googleapis.com/oauth2/v3/tokeninfo'
        TOTAT_REQUIRED_ACTIONS = [
          {controller: 'bulk_download', action: 'generate_curl_config'},
          {controller: 'studies', action: 'generate_manifest'}
        ]
        # these are API actions that we allow logged-in site users to access using
        # regular rails session validation & csrf protection, which can be useful
        # to save from having to put a token in a URL
        COOKIE_ALLOWED_ACTIONS = [
          {controller: 'reports', action: 'show'},
          {controller: 'expression', action: 'show'},
          {controller: 'annotations', action: 'cell_values'},
          {controller: 'annotations', action: 'gene_list'},
          {controller: 'studies', action: 'generate_manifest'}
        ]
        def authenticate_api_user!
          head 401 unless api_user_signed_in?
        end

        def authenticate_admin_api_user!
          head 403 unless api_user_signed_in? && current_api_user.admin
        end

        def set_current_api_user!
          current_api_user
        end

        def api_user_signed_in?
          current_api_user.present?
        end

        def current_api_user
          @current_api_user ||= get_current_api_user
        end

        # method to authenticate a user via Authorization Bearer tokens or Totat
        # the method first checks for an auth_code argument -- if that is present any bearer token will be ignored
        def get_current_api_user
          user = nil
          if TOTAT_REQUIRED_ACTIONS.include?({controller: controller_name, action: action_name})
            return find_user_from_totat
          elsif COOKIE_ALLOWED_ACTIONS.include?({controller: controller_name, action: action_name}) && current_user.present?
            # this is a request from a user logged into the website
            verify_authenticity_token
            verify_same_origin_request
            return current_user
          else
            api_access_token = extract_bearer_token(request)
            if api_access_token.present?
              user = User.find_by('api_access_token.access_token' => api_access_token)
              if user.nil?
                # extract user info from access_token
                user = find_user_from_token(api_access_token)
                if user.nil?
                  return nil
                end
              end
              # check for token expiry and unset user && api_access_token if expired/timed out
              # unsetting token prevents downstream FireCloud API calls from using an expired/invalid token
              if user.api_access_token_expired? || user.api_access_token_timed_out?
                user.update(api_access_token: nil)
                return nil
              else
                # update last_access_at
                user.update_last_access_at!
                return user
              end
            end
          end
          nil
        end

        private

        def find_user_from_totat
          # check for a valid totat/action
          if !params[:auth_code].present?
            return nil
          end
          Rails.logger.info "Authenticating user via auth_token: #{params[:auth_code]}"
          user = User.verify_totat(params[:auth_code], request.path)
          user.try(:update_last_access_at!)
          return user
        end

        def find_user_from_token(api_access_token)
          user = nil
          begin
            response = RestClient.get OAUTH_V3_TOKEN_INFO + "?access_token=#{api_access_token}"
            credentials = JSON.parse response.body
            now = Time.zone.now
            expires_in = credentials['expires_in'].to_i
            token_values = {
                'access_token' => api_access_token,
                'expires_in' => expires_in,
                'expires_at' => now + expires_in,
                'last_access_at' => now
            }
            email = credentials['email']
            user = User.find_by(email: email)
            if user.present?
              # store api_access_token to speed up retrieval next time
              user.update(api_access_token: token_values)
            else
              Rails.logger.error "Unable to retrieve user info from access token; user not present: #{email}"
              # no user is logged in because we don't have an account that matches the email
            end
          rescue RestClient::BadRequest => e
            Rails.logger.info 'Access token expired, cannot decode user info'
          rescue => e
            # we should only get here if a real error occurs, not if a token expires
            error_context = {
                auth_response_body: response.present? ? response.body : nil,
                auth_response_code: response.present? ? response.code : nil,
                auth_response_headers: response.present? ? response.headers : nil,
                token_present: api_access_token.present?
            }
            ErrorTracker.report_exception(e, nil, error_context)
            Rails.logger.error "Error retrieving user api credentials: #{e.class.name}: #{e.message}"
          end
          user
        end

        # attempt to extract the Authorization Bearer token
        def extract_bearer_token(request)
          if request.headers['Authorization'].present?
            token = request.headers['Authorization'].split.last
            token.gsub!(/(\'|\")/, '')
            token
          end
        end
      end
    end
  end
end

