# API client for registering public studies in DUOS

class DuosClient
  extend ServiceAccountManager
  include GoogleServiceClient
  include ApiHelpers

  attr_accessor :access_token, :api_root, :expires_at, :service_account_credentials, :duos_user_id

  GOOGLE_SCOPES = %w(email profile).freeze

  # hard-coded responses for ANVIL fields
  ANVIL_VALUES = {
    nihAnvilUse: 'I am not NHGRI funded and do not plan to store data in AnVIL',
    submittingToAnvil: false
  }.freeze

  # hard-coded responses for consentGroup fields
  CONSENT_VALUES = {
    accessManagement: 'open',
    dataLocation: 'Not Determined',
    generalResearchUse: false,
    diseaseSpecificUse: [],
    fileTypes: [],
    hmb: false,
    poa: false,
    nmds: false,
    gso: false,
    pub: false,
    col: false,
    irb: false,
    npu: false
  }.freeze

  # identifier to append to every description
  PLATFORM_ID = "(Platform: Single Cell Portal)".freeze

  # initialize new client and generate access token for auth
  #
  # * *params*
  #   - +service_account_key+: (String, Pathname) Path to service account JSON keyfile
  # * *return*
  #   - +DuosClient+ object
  def initialize(service_account = self.class.get_primary_keyfile)
    sub_host = Rails.env.production? ? 'prod' : 'dev'
    self.service_account_credentials = service_account
    self.access_token = self.class.generate_access_token(service_account)
    self.expires_at = Time.zone.now + self.access_token['expires_in']
    self.api_root = "https://consent.dsde-#{sub_host}.broadinstitute.org"

    if registered?
      self.duos_user_id = registration[:userId]
    end
  end

  # submit a request to DUOS API
  #
  # * *params*
  #   - +http_method+ (String, Symbol) HTTP method, e.g. :get, :post
  #   - +path+ (String) Relative URL path for API request being made
  #   - +payload+ (Hash) request body
  #   - +retry_count+ (Integer) Counter for tracking request retries
  #
  # * *returns*
  #   - (Hash) Parsed response body, if present
  #
  # * *raises*
  #   - (Faraday::Error) if HTTP request fails for any reason
  def process_api_request(http_method, path, payload: nil, retry_count: 0)
    # Log API call for auditing/tracking purposes
    Rails.logger.info "DUOS API request (#{http_method.to_s.upcase}) #{path}"
    # process request
    begin
      execute_http_request(http_method, path, payload)
    rescue Faraday::Error => e
      current_retry = retry_count + 1
      context = " encountered when requesting '#{path}', attempt ##{current_retry}"
      log_message = "#{e.message}: #{e.response_body}; #{context}"
      Rails.logger.error log_message
      if should_retry?(e.response_status) && retry_count < ApiHelpers::MAX_RETRY_COUNT
        retry_time = retry_interval_for(current_retry)
        sleep(retry_time)
        process_api_request(http_method, path, payload:, retry_count: current_retry)
      else
        ErrorTracker.report_exception(e,
                                      issuer,
                                      {
                                        method: http_method, url: path, payload:, retry_count:
                                      })
        error_message = parse_response_body(e.message)
        Rails.logger.error "Retry count exceeded when requesting '#{path}' - #{error_message}"
        raise e
      end
    end
  end

  # set headers correctly for requests
  # will change Content-Type to multipart for payload POST/PUT requests
  #
  # * *params*
  #   - +multipart+ (Boolean)
  #
  # * *returns*
  #   - (Hash)
  def headers_for_request(multipart: false)
    headers = get_default_headers
    headers['Content-Type'] = 'multipart/form-data' if multipart

    headers
  end

  # sub-handler for making external HTTP request
  # has special handling for mutlipart form posts using Faraday instead of RestClient
  #
  # * *params*
  #   - +http_method+ (String, Symbol) HTTP method, e.g. :get, :post
  #   - +path+ (String) Relative URL path for API request being made
  #   - +payload+ (Hash) Hash representation of request body
  #
  # * *returns*
  #   - (Hash) Parsed response body, if present
  #
  # * *raises*
  #   - (Faraday::Error) if HTTP request fails for any reason
  def execute_http_request(http_method, path, payload = nil)
    url = [api_root, path].join('/')
    multipart = is_multipart?(http_method, payload)
    headers = headers_for_request(multipart:)

    conn = Faraday.new(url:) do |f|
      f.request :multipart if multipart
      f.request :url_encoded
      f.adapter Faraday.default_adapter
      f.response :raise_error, include_request: true # raise exceptions on 4xx/5xx responses to mimic RestClient
    end

    response = conn.send(http_method) do |req|
      headers.each { |key, value| req.headers[key] = value }
      if multipart
        req.body = payload.transform_values do |value|
          value.is_a?(String) ? value : Faraday::UploadIO.new(StringIO.new(value.to_s), 'text/plain')
        end
      else
        req.body = payload
      end
    end
    handle_response(response)
  end

  # determine if request is a multipart form submission
  #
  # * *params*
  #   - +http_method+ (String, Symbol) HTTP method, e.g. :get, :post
  #   - +payload+ (Hash) request body
  #
  # * *returns*
  #   - (Boolean)
  def is_multipart?(http_method, payload)
    payload && %i[post put].include?(http_method.to_sym)
  end

  # API endpoints

  # basic health check
  #
  # * *returns*
  #   - (Boolean) T/F if NeMO is responding to requests
  def api_available?
    path = 'status'
    begin
      status = execute_http_request(:get, path)&.with_indifferent_access
      status && status[:ok]
    rescue Faraday::Error => e
      Rails.logger.error "DUOS service unavailable: #{e.message}"
      ErrorTracker.report_exception(e, nil, { method: :get, url: path, code: e.status })
      false
    end
  end

  # register a study in DUOS as a public dataset
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Hash) DUOS dataset registration of study
  #
  # * *raises*
  #   - (ArgumentError) if dataset schema is invalid
  def create_dataset(study)
    study_data = schema_from(study)
    validator = validate_dataset(study_data)
    if validator.any?
      raise ArgumentError, "DUOS dataset schema validation failed: #{validator.first[:error]}"
    end

    api_path = 'api/dataset/v3'
    process_api_request(:post, api_path, payload: { dataset: study_data.to_json })
  end

  # get a DUOS dataset by ID
  #
  # * *params*
  #   - +dataset_id+ (Integer) DUOS dataset id
  #
  # * *returns*
  #   - (Hash) DUOS dataset registration
  def dataset(dataset_id)
    api_path = "api/dataset/v2/#{dataset_id}"
    process_api_request(:get, api_path)
  end

  # update a DUOS dataset using an SCP study
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Hash) DUOS dataset registration of updated study
  #
  # * *raises*
  #   - (ArgumentError) if study is not registered in DUOS or dataset schema is invalid
  def update_dataset(study)
    raise ArgumentError, "#{study.accession} has no DUOS study ID" if study.duos_study_id.blank?

    study_data = schema_from(study)
    validator = validate_dataset(study_data)
    if validator.any?
      raise ArgumentError, "DUOS dataset schema validation failed: #{validator.first[:error]}"
    end

    api_path = "api/dataset/study/#{study.duos_study_id}"
    process_api_request(:put, api_path, payload: { dataset: study_data.to_json })
  end

  # get a DUOS study by ID
  #
  # * *params*
  #   - +dataset_id+ (Integer) DUOS dataset id
  #
  # * *returns*
  #   - (Hash) DUOS dataset registration
  def study(study_id)
    api_path = "api/dataset/study/#{study_id}"
    process_api_request(:get, api_path)
  end

  # delete a study in DUOS for non-production endpoints
  # removes associated dataset as well
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Boolean)
  #
  # * *raises*
  #   - (RuntimeError) if operation is attempted in production or study has no DUOS study id
  def delete_study(study)
    raise 'Operation not permitted' if Rails.env.production? || study.duos_study_id.blank?

    api_path = "api/dataset/study/#{study.duos_study_id}"
    process_api_request(:delete, api_path)
  end

  # handle a study redaction
  # in production, set to publicVisibility to false
  # otherwise delete the study
  #
  # * *params*
  #   - +study+ (Study)
  def redact_dataset(study)
    if Rails.env.production?
      update_dataset(study)
    else
      delete_study(study)
    end
  end

  # register service account with DUOS
  #
  # * *returns*
  #   - (Hash) Sam user registration of service account
  def register
    api_path = 'api/user'
    process_api_request(:post, api_path)
  end

  # retrieve DUOS registration for service account, like user ID and roles
  #
  # * *returns*
  #   - (Hash) SAM user registration of service account
  def registration
    api_path = 'api/user/me'
    process_api_request(:get, api_path)
  end

  # retrieve Sam-enabled statuses for service account
  #
  # * *returns*
  #   - (Hash) Sam status info of service account
  def sam_diagnostics
    api_path = 'api/sam/register/self/diagnostics'
    process_api_request(:get, api_path)
  end

  # check if a client is registered
  #
  # *returns*
  #  - (Boolean)
  def registered?
    registration&.[](:userId).present?
  rescue Faraday::Error
    false
  end

  # accept DUOS terms of service for service account
  #
  # * *returns*
  #  - (Boolean)
  def accept_tos
    api_path = 'api/sam/register/self/tos'
    process_api_request(:post, api_path)
  end

  # determine if the client needs to accept new terms
  #
  # * *returns*
  #  - (Boolean)
  def tos_accepted?
    sam_diagnostics&.[](:tosAccepted)
  rescue Faraday::Error
    false
  end

  # monkey-patch of issuer method since we're not loading the GCS SDK
  #
  # * *returns*
  #  - (String) service account email
  def issuer
    self.class.load_service_account_creds(service_account_credentials)&.issuer
  end

  # retrieve a dataset registration JSON schema
  #
  # * *returns*
  #   - (Hash)
  def dataset_schema
    api_path = 'schemas/dataset-registration/v1'
    process_api_request(:get, api_path)
  end

  # Schema/formatter methods

  # construct a DUOS schema object for registering a dataset
  # from https://consent.dsde-prod.broadinstitute.org/#/Schema/getDatasetRegistrationSchemaV1
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Hash) DUOS dataset schema object
  def schema_from(study, transform: true)
    consent_values = CONSENT_VALUES.merge(
      consentGroupName: duos_study_name(study), numberOfParticipants: study.donor_count, url: study.study_url
    )
    dataset = {
      dataSubmitterUserId: duos_user_id,
      studyName: duos_study_name(study),
      studyDescription: duos_study_description(study),
      dataTypes: study.data_types,
      publicVisibility: study.public,
      phenotypeIndication: study.diseases.join(', '),
      species: study.species_list.join(', '),
      dataCustodianEmail: study.data_custodians,
      piName: study.data_custodians.first,
      consentGroups: [consent_values]
    }.merge(ANVIL_VALUES).with_indifferent_access
  end

  # use JSON schema to validate dataset object
  #
  # * *params*
  #   - +dataset+ (Hash) DUOS dataset object
  #
  # * *returns*
  #   - (Enumerator) of validation errors, if any
  def validate_dataset(dataset)
    schema = JSONSchemer.schema(dataset_schema)
    schema.validate(dataset)
  end

  # version of study name with accession prepended
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (String)
  def duos_study_name(study)
    "#{study.accession} - #{study.name}"
  end

  # version of study description with the DUOS platform appended
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (String)
  def duos_study_description(study)
    "#{study.description} #{PLATFORM_ID}"
  end
end
