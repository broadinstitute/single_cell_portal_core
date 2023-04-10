##
# helper methods for handing external API requests/responses
# should be used in other classes via include, e.g. `include ApiHelpers`
##
module ApiHelpers
  # max number of retries if should_retry? is true
  MAX_RETRY_COUNT = 5

  # minimum amount of time to wait between failed requests
  MIN_INTERVAL = 5.0

  # base maximum amount of time to wait between failed requests, not including multiplier & jitter
  MAX_INTERVAL = 60.0

  # multiplier for retry intervals
  RETRY_MULTIPLIER = 1.75

  # jitter for retry randomization
  RETRY_JITTER = 0.125

  # known good HTTP status codes
  OK_STATUS_CODES = [200, 201, 202, 204, 206].freeze

  # 50x error codes that are acceptable to retry
  RETRY_STATUS_CODES = [502, 503, 504].freeze

  # get a retry interval for failed request based on count of number of retries
  #
  # * *params*
  #   - +count+ (Integer) => current retry count
  #
  # * *returns*
  #   - (Float) => amount of time in seconds to wait for next retry
  def retry_interval_for(count)
    # short-circuit in test env to prevent tests from running long
    return 0 if Rails.env.test?

    backoff = ExponentialBackoff.new(MIN_INTERVAL, MAX_INTERVAL)
    backoff.multiplier = RETRY_MULTIPLIER
    backoff.randomize_factor = RETRY_JITTER
    backoff.interval_at(count)
  end

  # get default HTTP headers for making requests
  #
  # * *params*
  #   - +content_type+ => Request Content-Type & Accept header value (defaults to application/json if not specified)
  #
  # * *returns*
  #   - (Hash) => Hash of default HTTP headers, e.g. Authorization, Content-Type
  def get_default_headers(content_type: nil)
    {
      'Authorization' => "Bearer #{self.valid_access_token['access_token']}",
      'Accept' => content_type || 'application/json',
      'Content-Type' => content_type || 'application/json',
      'x-app-id' => 'single-cell-portal',
      'x-domain-id' => "#{ENV['HOSTNAME']}"
    }
  end

  # check if OK response code was found
  #
  # * *params*
  #   - +code+ (Integer) => integer HTTP response code
  #
  # * *return*
  #   - +Boolean+ of whether or not response is a known 'OK' response
  def ok?(code)
    OK_STATUS_CODES.include?(code)
  end

  # determine if request should be retried based on response code, and will retry if necessary
  # only 502 (Bad Gateway), 503 (Service Unavailable), and 504 (Gateway Timeout) will be retried
  # all other 4xx and 5xx responses will not as they are deemed 'unrecoverable'
  #
  # * *params*
  #   - +code+ (Integer) => integer HTTP response code
  #
  # * *return*
  #   - +Boolean+ of whether or not response code indicates a retry should be executed
  def should_retry?(code)
    code.nil? || RETRY_STATUS_CODES.include?(code)
  end

  # merge hash of options into single URL query string, will reject query params with empty values
  #
  # * *params*
  #   - +opts+ (Hash) => hash of query parameter key/value pairs
  #
  # * *return*
  #   - +String+ of concatenated query params
  def merge_query_options(opts={})
    return nil if opts.blank?
    '?' + opts.reject {|k,v| k.blank? || v.blank?}.to_a.map {|k,v| "#{uri_encode(k)}=#{uri_encode(v)}"}.join('&')
  end

  # handle a RestClient::Response object
  #
  # * *params*
  #   - +response+ (String) => an RestClient response object
  #
  # * *return*
  #   - +Hash+ if response body is JSON, or +String+ of original body
  def handle_response(response)
    begin
      if ok?(response.code)
        response.body.present? ? parse_response_body(response.body) : true # blank body
      else
        response.message || parse_response_body(response.body)
      end
    rescue
      # don't report, just return
      response.message
    end
  end

  # parse a response body based on the content
  #
  # * *params*
  #   - +response_body+ (String) => an RestClient response body
  #
  # * *return*
  #   - +Hash+ if response body is JSON, or +String+ of original body
  def parse_response_body(response_body)
    begin
      JSON.parse(response_body)
    rescue
      response_body
    end
  end

  # determine if a response is JSON
  #
  # * *params*
  #   - +content+ (String) => RestClient response body
  #
  # * *returns*
  #   - (Boolean) => indication if content is JSON
  def is_json?(content)
    begin
      !!JSON.parse(content)
    rescue
      false
    end
  end

  # URI-encode parameters for use in API requests
  #
  # * *params*
  #   - +parameter+ (String) => Parameter to encode
  #
  # * *returns*
  #   - +String+ => URI-encoded parameter
  def uri_encode(parameter)
    CGI.escape(parameter.to_s)
  end
end
