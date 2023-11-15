# API client for interacting with Neuroscience Multi-Omic Data Portal (NeMO)
class NemoClient
  include ApiHelpers

  attr_accessor :api_root, :username, :password

  BASE_URL = 'https://beta-assets.nemoarchive.org/api'.freeze

  DEFAULT_HEADERS = {
    'Accept' => 'application/json',
    'Content-Type' => 'application/json'
  }.freeze

  # types of available entities
  ENTITY_TYPES = %w[collection file grant project publication sample subject].freeze

  # identifier format validator
  IDENTIFIER_FORMAT = /nemo:[a-z]{3}-[a-z0-9]{7}$/

  # base constructor
  #
  # * *return*
  #   - +NemoClient+ object
  def initialize(api_root: BASE_URL, username: ENV['NEMO_API_USERNAME'], password: ENV['NEMO_API_PASSWORD'])
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
        ErrorTracker.report_exception(e, nil,
                                      { method: http_method, url: path, payload:, retry_count: })
        error_message = parse_response_body(e.message)
        Rails.logger.error "Retry count exceeded when requesting '#{path}' - #{error_message}"
        raise e
      end
    end
  end

  # add basic HTTP auth header
  # TODO: remove after public release of API
  def authorization_header
    { Authorization: "Basic #{Base64.encode64("#{username}:#{password}")}" }
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
    headers = authorization_header.merge(DEFAULT_HEADERS)
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
      status = execute_http_request(:get, path)&.with_indifferent_access
      status && status[:status] == 'OK'
    rescue RestClient::ExceptionWithResponse => e
      Rails.logger.error "NeMO service unavailable: #{e.message}"
      ErrorTracker.report_exception(e, nil, { method: :get, url: path, code: e.http_code })
      false
    end
  end

  # generic handler to get an entity from the NeMO Identifier API
  #
  # * *params*
  #   - +entity_type+ (String, Symbol) => type of entity, from ENTITY_TYPES
  #   - +identifier+ (String) => file identifier, usually a UUID or nemo:[a-z]{3}-[a-z0-9]{7}$
  #
  # * *returns*
  #   - (Hash) => entity metadata, including associations and access URLs
  def fetch_entity(entity_type, identifier)
    validate_entity_type(entity_type)
    validate_identifier_format(identifier)
    path = "#{api_root}/#{entity_type}/#{uri_encode(identifier)}"
    process_api_request(:get, path)
  end

  # using a source entity, extract an association id from an array of associated entities
  # e.g. { name: 'foo', programs: [ {name: 'bar', url: 'https://nemoarchive.org/programs/nemo:1234'}] }
  # would yield 'nemo:1234'
  #
  # * *params*
  #   - +entity+ (Hash) => entity retrieved from API
  #   - +association+ (String, Symbol) => type of associated entities (e.g. programs, files, etc.)
  #   - +index+ (Integer) => Array position of associated entity to retrieve (defaults to 0)
  #   - +attribute+ (String, Symbol) => attribute name to extract ID from (e.g. :url)
  #
  # * *returns*
  #   - (String) NeMO API identifier in nemo:[a-z]{3}-[a-z0-9]{7}$ form
  def extract_associated_id(entity, association, index: 0, attribute: nil)
    associated_entity = entity[association.to_s]&.[](index)
    reference = attribute ? associated_entity&.[](attribute.to_s) : associated_entity
    reference&.split('/')&.last
  end

  ##
  # Convenience methods
  ##

  # get information about a collection
  #
  # * *params*
  #   - +identifier+ (String) => collection identifier
  #
  # * *returns*
  #   - (Hash) => collection metadata
  def collection(identifier)
    fetch_entity(:collection, identifier)
  end

  # get information about a file
  #
  # * *params*
  #   - +identifier+ (String) => file identifier
  #
  # * *returns*
  #   - (Hash) => File metadata
  def file(identifier)
    fetch_entity(:file, identifier)
  end

  # get information about a grant
  #
  # * *params*
  #   - +identifier+ (String) => grant identifier
  #
  # * *returns*
  #   - (Hash) => grant metadata
  def grant(identifier)
    fetch_entity(:grant, identifier)
  end

  # get information about a project
  #
  # * *params*
  #   - +identifier+ (String) => project identifier
  #
  # * *returns*
  #   - (Hash) => File metadata
  def project(identifier)
    fetch_entity(:project, identifier)
  end

  # get information about a publication
  #
  # * *params*
  #   - +identifier+ (String) => sample identifier
  #
  # * *returns*
  #   - (Hash) => publication metadata
  def publication(identifier)
    fetch_entity(:publication, identifier)
  end

  # get information about a sample
  #
  # * *params*
  #   - +identifier+ (String) => sample identifier
  #
  # * *returns*
  #   - (Hash) => Sample metadata
  def sample(identifier)
    fetch_entity(:sample, identifier)
  end

  # get information about a subject
  #
  # * *params*
  #   - +identifier+ (String) => sample identifier
  #
  # * *returns*
  #   - (Hash) => subject metadata
  def subject(identifier)
    fetch_entity(:subject, identifier)
  end

  private

  def validate_entity_type(entity_type)
    raise ArgumentError, "#{entity_type} not in #{ENTITY_TYPES}" unless ENTITY_TYPES.include?(entity_type.to_s)
  end

  def validate_identifier_format(identifier)
    raise ArgumentError, "#{identifier} does not match #{IDENTIFIER_FORMAT}" unless identifier.match(IDENTIFIER_FORMAT)
  end
end
