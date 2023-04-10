# Query Human Cell Atlas Azul service for metadata associated with both experimental and analysis data
# No ServiceAccountManager or GoogleServiceClient includes as all requests are unauthenticated for public data
class HcaAzulClient
  include ApiHelpers

  attr_accessor :api_root

  GOOGLE_SCOPES = %w[openid email profile].freeze
  BASE_URL = 'https://service.azul.data.humancellatlas.org'.freeze

  # maximum wait time for manifest generation
  MAX_MANIFEST_TIMEOUT = 30.seconds.freeze

  # List of accepted formats for manifest files
  MANIFEST_FORMATS = %w[compact full terra.bdbag terra.pfb curl].freeze

  # maximum number of results to return
  MAX_RESULTS = 200

  # maximum length of query string (in characters) for requests
  MAX_QUERY_LENGTH = 8192

  # Default headers for API requests
  DEFAULT_HEADERS = {
    'Accept' => 'application/json',
    'Content-Type' => 'application/json',
    'x-app-id' => 'single-cell-portal',
    'x-domain-id' => "#{ENV['HOSTNAME']}"
  }.freeze

  # Ignore stop words, as well as the term cell or cells as they are too common in Azul
  IGNORED_WORDS = (StudySearchService::STOP_WORDS + %w[cell cells]).uniq.freeze

  ##
  # Constructors & token management methods
  ##

  # base constructor
  #
  # * *return*
  #   - +HcaAzulClient+ object
  def initialize
    self.api_root = BASE_URL
  end

  ##
  # Abstract request handlers/heplers
  ##

  # submit a request to HCA Azul Service API
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
    Rails.logger.info "HCA Azul API request (#{http_method.to_s.upcase}) #{path}"
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
        process_api_request(http_method, path, payload: payload, retry_count: current_retry)
      else
        # we have reached our retry limit or the response code indicates we should not retry
        ErrorTracker.report_exception(e, nil, {
          method: http_method, url: path, payload: payload, retry_count: retry_count
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
    response = RestClient::Request.execute(method: http_method, url: path, payload: payload, headers: DEFAULT_HEADERS)
    # handle response using helper
    handle_response(response)
  end

  # FROM SCP-4592: Temporarily disable automatic retries while we investigate the rise in 503 errors from Azul
  def should_retry?(code)
    false
  end

  ##
  # API endpoint bindings
  ##

  # basic health check - does not give detailed status information, only checks for { 'up' => true }
  # bypasses process_api_request to avoid error handling/retries
  #
  # * *returns*
  #   - (Boolean) => T/F if Azul is responding to requests
  def api_available?
    path = "#{api_root}/health/cached"
    begin
      status = execute_http_request(:get, path)
      status && status['up']
    rescue RestClient::ExceptionWithResponse => e
      Rails.logger.error "Azul service unavailable: #{e.message}"
      ErrorTracker.report_exception(e, nil, { method: :get, url: path, code: e.http_code })
      false
    end
  end

  # check Azul service status via "fast" health check
  #
  # * *returns*
  #   - (Hash) => Hash of Azul services/endpoint status
  def service_information
    path = "#{api_root}/health/fast"
    begin
      execute_http_request(:get, path)
    rescue RestClient::ExceptionWithResponse => e
      Rails.logger.error "Azul service unavailable: #{e.message}"
      ErrorTracker.report_exception(e, nil, { method: :get, url: path, code: e.http_code })
      JSON.parse(e.http_body) if e.http_body.present? # response body should have more information than error message
    end
  end

  # get a list of all available catalogs
  #
  # * *returns*
  #   - (Hash) => Available catalogs, including :default_catalog
  def catalogs
    path = "#{api_root}/index/catalogs"
    process_api_request(:get, path)
  end

  # get a list of all available projects
  #
  # * *params*
  #   - +catalog+ (String) => HCA catalog name (optional)
  #   - +query+ (Hash) => query object from :format_query_object
  #   - +size+ (Integer) => number of results to return (default is 200)
  #
  # * *returns*
  #   - (Hash) => Available projects
  #
  # * *raises*
  #   - (ArgumentError) => if catalog is not in self.all_catalogs
  def projects(catalog: nil, query: {}, size: MAX_RESULTS)
    base_path = "#{api_root}/index/projects"
    base_path += "?filters=#{format_hash_as_query_string(query)}"
    base_path += "&size=#{size}"
    path = append_catalog(base_path, catalog)
    process_api_request(:get, path)
  end

  # simulate OR logic by splitting project queries on facet and joining results
  #
  # * *params*
  #   - +catalog+ (String) => HCA catalog name (optional)
  #   - +query+ (Hash) => query object from :format_query_object
  #   - +size+ (Integer) => number of results to return (default is 200)
  #
  # * *returns*
  #   - (Hash) => Available projects
  #
  # * *raises*
  #   - (ArgumentError) => if catalog is not in self.all_catalogs
  def projects_by_facet(catalog: nil, query: {}, size: MAX_RESULTS)
    all_results = { 'hits' => [], 'project_ids' => [] }
    isolated_queries = query.each_pair.map { |facet, filters| { facet => filters } }
    Rails.logger.info "Splitting above query into #{isolated_queries.size} requests and joining results"
    Parallel.map(isolated_queries, in_threads: isolated_queries.size) do |project_query|
      results = projects(catalog: catalog, query: project_query, size: size)
      results['hits'].each do |result|
        project_id = result['projects'].first['projectId']
        unless all_results['project_ids'].include?(project_id)
          all_results['project_ids'] << project_id
          all_results['hits'] << result
        end
      end
    end
    all_results
  end

  # get a list of all available catalogs
  #
  # * *params*
  #   - +catalog+ (String) => HCA catalog name (optional)
  #   - +project_id+ (String) => UUID of HCA project
  #
  # * *returns*
  #   - (Hash) => Available catalogs, including :default_catalog
  #
  # * *raises*
  #   - (ArgumentError) => if catalog is not in self.all_catalogs
  def project(project_id, catalog: nil)
    base_path = "#{api_root}/index/projects/#{project_id}"
    path = append_catalog(base_path, catalog)
    process_api_request(:get, path)
  end

  # get a metadata TSV file for a given HCA project UUID
  #
  # * *params*
  #   - +catalog+ (String) => HCA catalog name (optional)
  #   - +project_id+ (UUID) => HCA project UUID
  #   - +format+ (string) => manifest file format, from MANIFEST_FORMATS
  #
  # * *returns*
  #   - (Hash) => Hash response including an HTTP status code and a location to download
  #
  # * *raises*
  #   - (ArgumentError) => if catalog is not in self.all_catalogs or format is not in MANIFEST_FORMATS
  def project_manifest_link(project_id, catalog: nil, format: 'compact')
    validate_manifest_format(format)

    base_path = "#{api_root}/fetch/manifest/files"
    project_filter = { 'projectId' => { 'is' => [project_id] } }
    filter_query = format_hash_as_query_string(project_filter)
    base_path += "?filters=#{filter_query}&format=#{format}"
    path = append_catalog(base_path, catalog)
    # since manifest files are generated on-demand, keep making requests until the Status code is 302 (Found)
    # Status 301 means that the manifest is still being generated; if no manifest is ready after 30s, return anyway
    time_slept = 0
    manifest_info = process_api_request(:get, path)
    while manifest_info['Status'] == 301
      break if time_slept >= MAX_MANIFEST_TIMEOUT

      interval = manifest_info['Retry-After']
      Rails.logger.info "Manifest still generating for #{project_id} (#{format}), retrying in #{interval}"
      sleep interval
      time_slept += interval
      manifest_info = process_api_request(:get, path)
    end
    manifest_info
  end

  # search for available files using facets/terms
  #
  # * *params*
  #   - +catalog+ (String) => HCA catalog name (optional)
  #   - +query+ (Hash) => query object from :format_query_object
  #   - +size+ (Integer) => number of results to return (default is 200)
  #
  # * *returns*
  #   - (Hash) => List of files matching query
  def files(catalog: nil, query: {}, size: MAX_RESULTS)
    base_path = "#{api_root}/index/files"
    query_string = format_hash_as_query_string(query)
    base_path += "?filters=#{query_string}&size=#{size}"
    path = append_catalog(base_path, catalog)
    # make API request, but fold in project information to each result so that this is preserved for later use
    raw_results = process_api_request(:get, path)['hits']
    results = []
    raw_results.each do |result|
      files = result['files']
      project = result['projects'].first
      project_info = {
        'projectShortname' => project['projectShortname'].first,
        'projectId' => project['projectId'].first
      }
      files.each do |file|
        results << file.merge(project_info)
      end
    end
    results
  end

  ##
  # helper methods
  ##

  # take a list of facets and construct a query object to pass as query string parameters when searching
  #
  # * *params*
  #   - +facets+ (Array<Hash>) => Array of search facet objects from SearchController#index
  #
  # * *returns*
  #   - (Hash) => Hash of query object to be fed to :format_hash_as_query_string
  def format_query_from_facets(facets = [])
    query = {}.with_indifferent_access
    facets.each do |facet|
      safe_facet = facet.with_indifferent_access
      hca_term = FacetNameConverter.convert_schema_column(:alexandria, :azul, safe_facet[:id])
      next if hca_term.nil?

      scp_facet = facet[:db_facet]
      if scp_facet.is_numeric?
        min = safe_facet.dig(:filters, :min)
        max = safe_facet.dig(:filters, :max)
        unit = safe_facet.dig(:filters, :unit)
        min_seconds = scp_facet.calculate_time_in_seconds(base_value: min, unit_label: unit).to_i
        max_seconds = scp_facet.calculate_time_in_seconds(base_value: max, unit_label: unit).to_i
        # since organismAge only works with discrete value, we must convert this to a range query using 'within'
        # within query must have nested array, where min/max values are represented as arrays within query
        # multiple min/max ranges are processed with AND logic
        converted_term = hca_term == 'organismAge' ? 'organismAgeRange' : hca_term
        facet_query = { converted_term => { within: [[min_seconds, max_seconds]] } }
      else
        filter_values = safe_facet[:filters].map { |filter| filter[:name] }
        facet_query = { hca_term => { is: filter_values } }
      end
      if query.key?(hca_term)
        existing_filters = query.dig(hca_term, :is)
        new_query = { hca_term => { is: (existing_filters + facet_query.dig(hca_term, :is)).uniq } }
        query.merge! new_query
      else
        query.merge! facet_query
      end
    end
    query
  end

  # find matching facets based on keyword list along with filters that contain items from term_list
  # to be passed to :format_query_from_facets
  # since Azul does not support keyword searching, we must find a match for a corresponding facet and treat this as
  # the search request
  # will ignore very common/short words, including known stop words (see StudySearchService::STOP_WORDS)
  #
  # * *params*
  #   - +term_list+ (Array<String>) => Array of terms to query
  #
  # * *returns*
  #   - (Array<Hash>) => Array of facet objects to be fed to :format_query_from_facets
  def format_facet_query_from_keyword(term_list = [])
    matching_facets = []
    sanitized_terms = filter_term_list(term_list)
    sanitized_terms.each do |term|
      facets = SearchFacet.find_facets_from_term(term)
      next if facets.empty?

      facets.each do |facet|
        # mock a faceted search match, appending in all possible filter matches
        filters = facet.find_filter_matches(term, filter_list: :filters_with_external).map do |t|
          [{ id: t, name: t }.with_indifferent_access]
        end.flatten
        match = {
          id: facet.identifier,
          filters: filters,
          db_facet: facet,
          keyword_conversion: true # mark this as a 'converted' facet to control whether showing facet match badges
        }.with_indifferent_access
        matching_facets << match unless matching_facets.include? match
      end
    end
    matching_facets
  end

  # merge multiple queries together, e.g. :format_query_from_facets & :format_query_from_terms
  #
  # * *params*
  #   - +query_objects+ (Array<Hash>) => array of query objects to merge together
  #
  # * *returns*
  #   - (Hash) => Hash of query object to be fed to :format_hash_as_query_string
  def merge_query_objects(*query_objects)
    merged_query = {}.with_indifferent_access
    query_objects.compact.each do |query|
      query.each_pair do |facet_name, opts|
        if merged_query[facet_name].nil?
          merged_query[facet_name] = opts
        else
          opts.each_pair do |operator, values|
            values.each do |value|
              merged_query[facet_name][operator] << value unless merged_query[facet_name][operator].include?(value)
            end
          end
        end
      end
    end
    merged_query
  end

  # take a Hash/JSON object and format as a query string parameter
  #
  # * *params*
  #   - +query_params+ (Hash) => Hash of query parameters
  #
  # * *returns*
  #   - (String) => URL-encoded string version of query parameters
  def format_hash_as_query_string(query_params)
    # replace Ruby => assignment operators with JSON standard colons (:)
    sanitized_params = query_params.to_s.gsub(/=>/, ':')
    CGI.escape(sanitized_params)
  end

  # determine if a requested query is too long and would result in an HTTP 413 Payload Too Large exception
  #
  # * *params*
  #   - +query_params+ (Hash) => Hash of query parameters
  #
  # * *returns*
  #   - (Boolean) => T/F if query would be too large
  def query_too_large?(query_params)
    formatted_query = format_hash_as_query_string(query_params)
    formatted_query.size >= MAX_QUERY_LENGTH
  end

  # append the HCA catalog name, if passed to a method
  #
  # * *params*
  #   - +api_path+ (String) => URL path for API request
  #   - +catalog+ (String) => name of HCA catalog
  #
  # * *returns*
  #   - (String) => URL path with catalog name appended, if present
  #
  # * *raises*
  #   - (ArgumentError) => if catalog is not in self.all_catalogs
  def append_catalog(api_path, catalog)
    return api_path unless catalog.present?

    validate_catalog_name(catalog)
    delimiter = api_path.include?('?') ? '&' : '?'
    "#{api_path}#{delimiter}catalog=#{catalog}"
  end

  # filter irrelevant terms from keyword query to increase relevance of search
  #
  # * *params*
  #   - +term_list+ (Array) => list of terms to filter
  #
  # * *returns*
  #   - (Array) => filtered list of terms
  def filter_term_list(term_list)
    (term_list.map(&:downcase) - IGNORED_WORDS).reject { |t| t.size < 3 }
  end

  private

  # validate that a catalog exists by checking the list of available public catalogs
  def validate_catalog_name(catalog)
    all_catalogs = catalogs['catalogs'].reject { |_, cat| cat['internal'] }.keys.sort
    unless all_catalogs.include?(catalog)
      error = ArgumentError.new("#{catalog} is not a valid catalog: #{all_catalogs.join(',')}")
      api_method = caller_locations[1]&.label # caller will be 2nd in stack, as first will be append_catalog
      ErrorTracker.report_exception(error, nil, { catalog: catalog, method: api_method })
      raise error
    end
  end

  # validate requested format is valid
  def validate_manifest_format(format)
    unless MANIFEST_FORMATS.include?(format)
      error = ArgumentError.new("#{format} is not a valid format: #{MANIFEST_FORMATS.join(',')}")
      api_method = caller_locations.first&.label
      ErrorTracker.report_exception(error, nil, { format: format, method: api_method })
      raise error
    end
  end
end
