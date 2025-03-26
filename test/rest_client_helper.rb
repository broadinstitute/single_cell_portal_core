require 'rest_client'
RestClient::Exception.module_eval do
  def http_code
    if @response
      @response.try(:code)&.to_i || @response.try(:http_code)&.to_i || @response
    else
      @initial_response_code
    end
  end
end
