##
# API client bindings for retrieving information about Terra Data Repo datasets/snapshots/schemas from their API
##
class DataRepoClient
  extend ServiceAccountManager
  include GoogleServiceClient
  include ApiHelpers

  attr_accessor :access_token, :api_root, :storage, :expires_at, :service_account_credentials

  # Google authentication scopes necessary for querying TDR API
  GOOGLE_SCOPES = %w(openid email profile https://www.googleapis.com/auth/devstorage.read_only)
   # Base API URL to request against
  BASE_URL = Rails.application.config.tdr_api_base_url.freeze
  # Hostname of repo, needed for parsing out DRS identifiers
  REPOSITORY_HOSTNAME = URI(BASE_URL).host.freeze
  # prefix used to identify valid DRS ids
  DRS_PREFIX = "drs://#{REPOSITORY_HOSTNAME}/".freeze

  # control variables
  SORT_DIRECTIONS = %w(asc desc).freeze
  SORT_OPTIONS = %w(name description created_date).freeze
  DATASET_INCLUDE_FIELDS = %w(NONE SCHEMA ACCESS_INFORMATION PROFILE DATA_PROJECT STORAGE).freeze
  ALL_DATASET_FIELDS = %w(SCHEMA ACCESS_INFORMATION PROFILE DATA_PROJECT STORAGE).freeze

  ##
  # Constructors & token management methods
  ##

  # initialize is called after instantiating with DataRepoClient.new
  # will set the access token, TDR base API URL  root and GCP storage driver instance
  #
  # * *params*
  #   - +service_account_key+: (String, Pathname) => Path to service account JSON keyfile
  # * *return*
  #   - +DataRepoClient+ object
  def initialize(service_account = self.class.get_read_only_keyfile)
    # GCS storage driver attributes
    storage_attr = {
      project_id: self.class.compute_project,
      timeout: 3600,
      credentials: service_account
    }

    self.service_account_credentials = service_account
    self.access_token = self.class.generate_access_token(service_account)
    self.storage = Google::Cloud::Storage.new(**storage_attr)
    self.expires_at = Time.zone.now + self.access_token['expires_in']
    self.api_root = BASE_URL
  end

  ##
  # Abstract request handlers
  ##

  # submit a request to TDR API
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
  #   - (RestClient::Exception) => if HTTP request fails for any reason  def process_api_request(http_method, path, payload: nil, retry_count: 0)
  def process_api_request(http_method, path, payload: nil, retry_count: 0)
    # Log API call for auditing/tracking purposes
    Rails.logger.info "Terra Data Repo API request (#{http_method.to_s.upcase}) #{path}"
    # process request
    begin
      response = RestClient::Request.execute(method: http_method, url: path, payload: payload, headers: get_default_headers)
      # handle response using helper
      handle_response(response)
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
        ErrorTracker.report_exception(e, self.issuer, {
          method: http_method, url: path, payload: payload, retry_count: retry_count
        })
        error_message = parse_response_body(e.message)
        Rails.logger.error "Retry count exceeded when requesting '#{path}' - #{error_message}"
        raise e
      end
    end
  end

  ##
  # API ENDPOINT BINDINGS
  ##

  ##
  # Status
  ##

  # get more detailed status information about TDR API
  # this method doesn't use process_api_request as we want to preserve error states rather than catch and suppress them
  #
  # * *return*
  #   - +Hash+ with health status information for various TDR services or error response
  def api_status
    path = self.api_root + '/status'
    begin
      response = RestClient::Request.execute(method: :get, url: path, headers: get_default_headers)
      JSON.parse(response.body)
    rescue RestClient::ExceptionWithResponse => e
      Rails.logger.error "Terra Data Repo status error: #{e.message}"
      e.response
    end
  end

  # determine if TDR API is currently up/available
  #
  # * *return*
  #   - +Boolean+ indication of TDR current root status
  def api_available?
    begin
      response = self.api_status
      response.is_a?(Hash) && response['ok']
    rescue => e
      false
    end
  end

  ##
  # Datasets
  ##

  # fetch all available datasets
  #
  # * *params*
  #   - +direction+ (String) => Sort direction (default: desc)
  #   - +filter+ (String) => Filter the results where this string is a case insensitive match in the name or description.
  #   - +limit+ (Integer) => The numbers datasets to retrieve
  #   - +offset+ (Integer) => The number of datasets to skip before when retrieving the next page
  #   - +sort+ (String) => The field to use for sorting: (name, description, created_date)
  #
  # * *returns*
  #   - (Array<Hash>) => Array of dataset JSON attributes
  def get_datasets(direction: 'desc', filter: nil, limit: 100, offset: 0, sort: 'name')
    validate_argument(:direction, direction, SORT_DIRECTIONS)
    validate_argument(:sort, sort, SORT_OPTIONS)
    query_opts = merge_query_options({direction: direction, filter: filter, limit: limit, offset: offset, sort: sort})
    path = api_root + '/api/repository/v1/datasets' + query_opts
    process_api_request(:get, path)
  end

  # fetch a single dataset
  #
  # * *params*
  #   - +dataset_id+ (String: UUID) => Dataset UUID
  #   - +include+ (Array) => Dataset fields to return from DATASET_INCLUDE_FIELDS (default: SCHEMA,PROFILE,DATA_PROJECT,STORAGE)
  #
  # * *returns*
  #   - (Hash) => Hash of dataset JSON attributes
  def get_dataset(dataset_id, include: ALL_DATASET_FIELDS)
    path = api_root + "/api/repository/v1/datasets/#{dataset_id}"
    if include.any?
      validate_argument(:include, include, DATASET_INCLUDE_FIELDS)
      query_opts = include.map {|i| "include=#{i}"}.join('&')
      path += "?#{query_opts}"
    end
    process_api_request(:get, path)
  end

  ##
  # Snapshots
  ##

  # fetch all available snapshots
  #
  # * *params*
  #   - +datasetIds+ (Array<String>) => Filter the results where these datasetIds are source datasets.
  #   - +direction+ (String) => Sort direction (default: desc)
  #   - +filter+ (String) => Filter the results where this string is a case insensitive match in the name or description.
  #   - +limit+ (Integer) => The numbers datasets to retrieve
  #   - +offset+ (Integer) => The number of datasets to skip before when retrieving the next page
  #   - +sort+ (String) => The field to use for sorting: (name, description, created_date)
  #
  # * *returns*
  #   - (Array<Hash>) => Array of snapshot JSON atributes
  def get_snapshots(datasetIds: [], direction: 'desc', filter: nil, limit: 100, offset: 0, sort: 'name')
    validate_argument(:direction, direction, SORT_DIRECTIONS)
    validate_argument(:sort, sort, SORT_OPTIONS)
    query_opts = merge_query_options(
      {
        datasetIds: datasetIds.join(','), direction: direction, filter: filter,
        limit: limit, offset: offset, sort: sort
      }
    )
    path = api_root + '/api/repository/v1/snapshots' + query_opts
    process_api_request(:get, path)
  end

  # fetch an individual snapshot
  #
  # * *params*
  #   - +snapshot_id+ (UUID) => Snapshot UUID
  #
  # * *returns*
  #   - (Hash) => Hash of snapshot JSON attributes
  def get_snapshot(snapshot_id)
    path = api_root + "/api/repository/v1/snapshots/#{snapshot_id}"
    process_api_request(:get, path)
  end

  # find all tables that pertain to files for a given snapshot
  #
  # * *params*
  #   - +snapshot_id+ (UUID) => Snapshot UUID
  #   - +file_id+ (String) => Snapshot file ID, usually the last UUID component from a DRS ID
  #
  # * *returns*
  #   - (Hash) => Hash detail of file object with path/size/checksum info, and a fileDetail object with a gs accessUrl
  def get_snapshot_file_info(snapshot_id, file_id)
    path = api_root + "/api/repository/v1/snapshots/#{snapshot_id}/files/#{file_id}"
    process_api_request(:get, path)
  end

  ##
  # Query methods
  ##

  # query existing snapshot indexes to return denormalized row-level entries from the index
  #
  # * *params*
  #   - +query_json+ (String) => ElasticSearch DSL query string, from DataRepoClient#generate_query_from_facets
  #   - +limit+ (Integer) => limit on results returned, default: 1000
  #   - +offset+ (Integer) => offset row count on results, default: 0
  #   - +snapshot_ids+ (Array<UUID>) => restrict query to provided snapshots, default will query all available indexes
  #
  # * *returns*
  #   - (Array<Hash>) => Array of row-level results, with all columns present in index (there will be a lot of duplication)
  def query_snapshot_indexes(query_json, limit: 10000, offset: 0, snapshot_ids: [])
    query_opts = merge_query_options({limit: limit, offset: offset})
    path = api_root + '/api/repository/v1/search/query' + query_opts
    payload = {
      query: query_json.to_json, # extra JSON encoding needed here to escape quotes and other control characters
      snapshotIds: snapshot_ids
    }.to_json
    process_api_request(:post, path, payload: payload)
  end

  # generate a query string in ElasticSearch query DSL
  # will also convert SCP metadata convention names to HCA/TIM names for TDR query
  # see https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl.html for more information
  #
  # * *params*
  #   - +selected_facets+ (Array<Hash>) => Array of hashes representing query facets & filter values, passed from Api::V1::SearchController#index
  #                              e.g. [{id: :species, filters: [{id: 'NCBITaxon9609', name: 'Homo sapiens'}]},
  #                                    {id: :disease, filters: [{id: 'MONDO_0018076', name: 'tuberculosis', },
  #                                    {id: 'MONDO_0005105', name: 'melanoma'}]}]
  #
  # * *returns*
  #   - (Hash) => Hash representation of query in ElasticSearch query DSL (must be cast to JSON for use in DataRepoClient#query_snapshot_indexes)
  #                 e.g. "{:query_string=>{:query=>"(genus_species:NCBITaxon9609 OR genus_species:Homo sapiens) AND
  #                         (disease:MONDO_0018076 OR disease:tuberculosis OR disease:MONDO_0005105 OR disease:melanoma)"}}"
  def generate_query_from_facets(selected_facets)
    formatted_elements = []
    selected_facets.each do |search_facet|
      facet_id = search_facet[:id]
      # convert to names used in TDR, or fall back to SCP name if not found
      tdr_column = FacetNameConverter.convert_schema_column(:alexandria, :tim, facet_id) || facet_id
      if search_facet[:filters].is_a? Hash # this is a numeric facet w/ min/max/unit
        # cast to integer for matching; TODO: determine correct unit/datatype and convert
        filters = ["#{search_facet.dig(:filters, :min).to_i}-#{search_facet.dig(:filters, :max).to_i}"]
      else
        filters = search_facet[:filters].map(&:values).flatten
      end
      elements = filters.map {|filter| "([#{tdr_column}]:\"#{filter}\")" }.uniq
      formatted_elements << "#{elements.join(' OR ')}"
    end
    { query_string: { query: formatted_elements.join(' AND ') } }
  end

  # generate query json from a list of keywords/terms to search titles/descriptions
  #
  # * *params*
  #   - +terms+ (Array<String>) => Array of keywords/terms
  #
  # * *returns*
  #   - (Hash) => Hash representation of query in ElasticSearch query DSL (must be cast to JSON for use in DataRepoClient#query_snapshot_indexes)
  def generate_query_from_keywords(term_list)
    name_field = FacetNameConverter.convert_schema_column(:alexandria, :tim, :study_name)
    desc_field = FacetNameConverter.convert_schema_column(:alexandria, :tim, :study_description)
    formatted_elements = []
    [name_field, desc_field].each do |tdr_column|
      elements = term_list.map { |term| "[#{tdr_column}]:\"#{term}\"" }
      formatted_elements << "(#{elements.join(' OR ')})"
    end
    # this is a logical OR query as a match in either name or description is valid
    { query_string: { query: formatted_elements.join(' OR ') } }
  end

  # generate a query json using only a list of project_ids
  # will return all result rows for the given project(s) to ensure all available files are found
  #
  # * *params*
  #   - +project_ids+ (Array<String>) => Array of HCA project UUIDs
  #
  # * *returns*
  #   - (Hash) => Hash representation of query in ElasticSearch query DSL (must be cast to JSON for use in DataRepoClient#query_snapshot_indexes)
  def generate_query_for_projects(project_ids)
    project_query = project_ids.map { |project_id| "(project_id: #{project_id})" }
    { query_string: { query: project_query.join(' OR ') } }
  end

  # merge two query json objects together, if necessary
  #
  # * *params*
  #   - +facet_query+ (Hash) => query json from generate_query_from_facets
  #   - +term_query+ (Hash) => query json from generate_query_from_keywords
  #
  # * *returns*
  #   - (Hash) => Hash representation of query in ElasticSearch query DSL (must be cast to JSON for use in DataRepoClient#query_snapshot_indexes)
  #
  # * *raises*
  #   - (ArgumentError) => if both query objects are empty
  def merge_query_json(facet_query:, term_query:)
    raise ArgumentError.new('Must supply either facet_query or term_query to merge') if facet_query.nil? && term_query.nil?
    # merge two together, otherwise return which ever is present
    if facet_query.present? && term_query.present?
      {query_string: {query: "(#{facet_query.dig(:query_string, :query)}) AND (#{term_query.dig(:query_string, :query)})"}}
    elsif facet_query.present? && term_query.nil?
      facet_query
    else
      term_query
    end
  end

  ##
  # DRS File methods
  ##

  # get a file using a DRS identifier
  #
  # * *params*
  #   - +drs_id+ (String) => A DRS idenfifier, formatted as drs://[repository_hostname]/v1_[collection_id]_[file_id], where
  #                          [repository_hostname] is a domain name, e.g. jade.datarepo-dev.broadinstitute.org,
  #                          [collection_id] is a UUID of a collection, and
  #                          [file_id] is a UUID of a file object, e.g:
  #                          drs://jade.datarepo-dev.broadinstitute.org/v1_fcaee9e0-4745-4006-9718-7d048a846d96_5009a1f8-c2ee-4ceb-8ddb-40c3ddee5472
  #
  # * *returns*
  #   - (Hash) => Hash detail of file object with path/size/checksum info, and a fileDetail object with a gs accessUrl
  #
  # * *raises*
  #   - (ArgumentError) => if drs_id is not formatted correctly
  def get_drs_file_info(drs_id)
    formatted_id = parse_drs_id(drs_id)
    path = api_root + '/ga4gh/drs/v1/objects/' + formatted_id
    process_api_request(:get, path)
  end

  # get back a GS url from a DRS file id
  #
  # * *params*
  #   - +drs_id+ (String) => A DRS identifier, formatted as drs://[repository_hostname]/v1_[collection_id]_[file_id]
  #   - +access_type+ (String, Symbol) => type of access, either :gs or :https
  #
  # * *returns*
  #   - (String) => a url pointing to a file in a bucket, can be gs:// or https://
  #
  # * *raises*
  #   - (ArgumentError) => if drs_id is not formatted correctly
  def get_access_url_from_drs_id(drs_id, access_type)
    file_info = get_drs_file_info(drs_id)
    access_info = file_info.dig('access_methods').detect {|access| access.dig('type') == access_type.to_s}
    if access_info.present?
      access_info.dig('access_url', 'url')
    else
      nil
    end
  end

  # parse a DRS identifier into a usable ID for DataRepoClient#get_drs_file_info
  #
  # * *params*
  #   - +drs_id+ (String) => A DRS identifier, formatted as drs://[repository_hostname]/v1_[collection_id]_[file_id]
  #
  # * *returns*
  #   - (String) => an identifier to be used in DataRepoClient#get_drs_file_info
  #
  # * *raises*
  #   - (ArgumentError) => if drs_id is not formatted correctly
  def parse_drs_id(drs_id)
    raise ArgumentError.new("\"#{drs_id}\" is not a valid DRS ID") unless drs_id.starts_with?(DRS_PREFIX)
    drs_id.split(DRS_PREFIX).last
  end

  private

  # generic validator for an argument to a method
  #
  # * *params*
  #   - +name+ (String, Symbol) => argument name
  #   - +value+ (Various) => Value for argument
  #   - +control+ (Array) => Array of acceptable values
  #
  # * *raises*
  #   - (ArgumentError) => if value is not a member of control
  def validate_argument(name, value, control)
    if value.is_a?(Array)
      # use array subtraction to find non-control values
      invalid = value - control
      if invalid.any?
        raise ArgumentError.new("Invalid values for \"#{name}: #{invalid.join(',')}\", must be a member of \"#{control}\"")
      end
    else
      raise ArgumentError.new("Invalid value for \"#{name}: #{value}\"; must be a member of \"#{control}\"") if !control.include?(value)
    end
  end
end
