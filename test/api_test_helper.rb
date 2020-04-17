ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

module Requests
  module JsonHelpers
    # parse a response body as JSON
    def json
      if @response.content_type == 'application/json'
        JSON.parse(@response.body)
      else
        @response.body
      end
    end
  end

  module HttpHelpers
    # execute an HTTP call of the specified method to a given path (with optional payload), setting accept & content_type
    # to :json and prepending the authorization bearer token to the headers
    def execute_http_request(method, path, request_payload={})
      token = @user.present? ? "Bearer #{@user.api_access_token[:access_token]}" : nil
      headers = token.present? ? {authorization: "Bearer #{token}"} : {}
      send(method.to_sym, path, params: request_payload, as: :json, headers: headers)
    end
  end
end
