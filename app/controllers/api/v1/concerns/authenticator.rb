module Api
  module V1
    module Concerns
      module Authenticator
        extend ActiveSupport::Concern
        OAUTH_V3_TOKEN_INFO = 'https://www.googleapis.com/oauth2/v3/tokeninfo'

        def authenticate_api_user!
          head 401 unless api_user_signed_in?
        end

        def set_current_api_user!
          current_api_user
        end

        def api_user_signed_in?
          current_api_user.present?
        end

        # method to authenticate a user via Authorization Bearer tokens
        def current_api_user
          api_access_token = extract_bearer_token(request)
          if api_access_token.present?
            user = User.find_by('api_access_token.access_token' => api_access_token)
            if user.nil?
              # extract user info from access_token
              begin
                response = RestClient.get OAUTH_V3_TOKEN_INFO + "?access_token=#{api_access_token}"
                credentials = JSON.parse response.body
                now = Time.zone.now
                token_values = {
                    'access_token' => api_access_token,
                    'expires_in' => credentials['expires_in'],
                    'expires_at' => now + credentials['expires_in'].to_i,
                    'last_access_at' => now
                }
                email = credentials['email']
                user = User.find_by(email: email)
                if user.present?
                  # store api_access_token to speed up retrieval next time
                  user.update(api_access_token: token_values)
                else
                  Rails.logger.error "Unable to retrieve user info from access token; user not present: #{email}"
                  return nil # no user is logged in because we don't have an account that matches the email
                end
              rescue RestClient::BadRequest => e
                Rails.logger.info 'Access token expired, cannot decode user info'
                return nil
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
                return nil
              end
            end
            # check for token expiry and unset user && api_access_token if expired/timed out
            # unsetting token prevents downstream FireCloud API calls from using an expired/invalid token
            if user.api_access_token_expired? || user.api_access_token_timed_out?
              user.update(api_access_token: nil)
              nil
            else
              # update last_access_at
              user.update_last_access_at!
              user
            end
          elsif controller_name == 'search' && action_name == 'bulk_download'
            Rails.logger.info "Authenticating user via auth_token: #{params[:auth_code]}"
            return nil if params[:auth_code].blank?
            user = User.find_by(totat: params[:auth_code].to_i)
            user.try(:update_last_access_at!)
            user
          end
        end

        private

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

