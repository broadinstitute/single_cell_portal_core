# API client for interacting with Neurpscience Multi-Omic Data Portal (NeMO)
class NemoClient
  include ApiHelpers

  attr_accessor :api_root, :username, :password

  BASE_URL = 'https://portal.nemoarchive.org/api'.freeze

  DEFAULT_HEADERS = {
    'Accept' => 'application/json',
    'Content-Type' => 'application/json'
  }.freeze

  # base constructor
  #
  # * *return*
  #   - +NemoClient+ object
  def initialize(api_root: BASE_URL, username: nil, password: nil)
    self.api_root = api_root.chomp('/')
    self.username = username
    self.password = password
  end

  # submit a request to NeMO API
  #
  # * *params*
  #   - +http_method+ (String, Symbol) => HTTP method, e.g. :get, :post
  #   - +path+ (String) => Relative URL path for API request being made
  #   - +payload+ (Hash) => Hash representation of request body
  #   - +retry_count+ (Integer) => Counter for tracking request retries
  #
  # * *returns*
  #   - (Hash) => Parsed response body, if present
  #
  # * *raises*
  #   - (RestClient::Exception) => if HTTP request fails for any reason
  def process_api_request(http_method, path, payload: nil, retry_count: 0)
    # Log API call for auditing/tracking purposes
    Rails.logger.info "NeMO API request (#{http_method.to_s.upcase}) #{path}"
    # process request
    begin
      execute_http_request(http_method, path, payload)
    rescue RestClient::Exception => e
      current_retry = retry_count + 1
      context = " encountered when requesting '#{path}', attempt ##{current_retry}"
      log_message = "#{e.message}: #{e.http_body}; #{context}"
      Rails.logger.error log_message
      # only retry if status code indicates a possible temporary error, and we are under the retry limit and
      # not calling a method that is blocked from retries
      if should_retry?(e.http_code) && retry_count < ApiHelpers::MAX_RETRY_COUNT
        retry_time = retry_interval_for(current_retry)
        sleep(retry_time)
        process_api_request(http_method, path, payload:, retry_count: current_retry)
      else
        # we have reached our retry limit or the response code indicates we should not retry
        ErrorTracker.report_exception(e, nil, {
          method: http_method, url: path, payload:, retry_count:
        })
        error_message = parse_response_body(e.message)
        Rails.logger.error "Retry count exceeded when requesting '#{path}' - #{error_message}"
        raise e
      end
    end
  end

  # sub-handler for making external HTTP request
  # does not have error handling, this is done by process_api_request
  # allows for some methods to implement their own error handling (like health checks)
  #
  # * *params*
  #   - +http_method+ (String, Symbol) => HTTP method, e.g. :get, :post
  #   - +path+ (String) => Relative URL path for API request being made
  #   - +payload+ (Hash) => Hash representation of request body
  #
  # * *returns*
  #   - (Hash) => Parsed response body, if present
  #
  # * *raises*
  #   - (RestClient::Exception) => if HTTP request fails for any reason
  def execute_http_request(http_method, path, payload = nil)
    headers = {
      'user' => username,
      'password' => password
    }.merge(DEFAULT_HEADERS)
    response = RestClient::Request.execute(method: http_method, url: path, payload:, headers:)
    # handle response using helper
    handle_response(response)
  end

  # API endpoints

  # basic health check
  #
  # * *returns*
  #   - (Boolean) => T/F if NeMO is responding to requests
  def api_available?
    path = "#{api_root}/status"
    begin
      # since this is a no-body response, ApiHelpers#handle_response will return true
      execute_http_request(:get, path)
    rescue RestClient::ExceptionWithResponse => e
      Rails.logger.error "NeMO service unavailable: #{e.message}"
      ErrorTracker.report_exception(e, nil, { method: :get, url: path, code: e.http_code })
      false
    end
  end

  # get information about a file
  #
  # * *params*
  #   - +identifier+ (String) => file identifier, usually a UUID or nemo:[a-z]{3}-[a-z0-9]{7}$
  #
  # * *returns*
  #   - (Hash) => File metadata, including associations and access URLs
  def file(identifier)
    path = "#{api_root}/files/#{uri_encode(identifier)}"
    process_api_request(:get, path)
  end

  # get information about a sample
  #
  # * *params*
  #   - +identifier+ (String) => sample identifier, usually a UUID or nemo:[a-z]{3}-[a-z0-9]{7}$
  #
  # * *returns*
  #   - (Hash) => Sample metadata, including associations and access URLs
  def sample(identifier)
    path = "#{api_root}/samples/#{uri_encode(identifier)}"
    process_api_request(:get, path)
  end
end
