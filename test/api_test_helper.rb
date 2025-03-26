require 'simplecov_helper'
require 'rest_client_helper'

ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

# from https://github.com/omniauth/omniauth/wiki/Integration-Testing
OmniAuth.config.test_mode = true

module Requests
  module JsonHelpers
    # parse a response body as JSON
    def json
      if @response.content_type.include? 'application/json'
        JSON.parse(@response.body)
      else
        @response.body
      end
    end
  end

  module HttpHelpers
    # execute an HTTP call of the specified method to a given path (with optional payload), setting accept & content_type
    # to :json and prepending the authorization bearer token to the headers
    def execute_http_request(method, path, request_payload: {}, user: @user)
      token = user.present? ? "Bearer #{user.api_access_token[:access_token]}" : nil
      headers = token.present? ? {authorization: "Bearer #{token}"} : {}
      send(method.to_sym, path, params: request_payload, as: :json, headers: headers)
    end

    # sign in the user and also update their last_active
    def sign_in_and_update(user)
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
        :provider => 'google_oauth2',
        :uid => user.uid,
        :email => user.email
      })
      sign_in user
      user.update_last_access_at!
    end
  end
end

