# patch to handle issues of inconsistency
module RestClient
  class Exception < RuntimeError
    def http_code
      # return integer for compatibility
      if @response
        @response.try(:code)&.to_i || @response.try(:http_code)&.to_i || @response
      else
        @initial_response_code
      end
    end
  end
end
