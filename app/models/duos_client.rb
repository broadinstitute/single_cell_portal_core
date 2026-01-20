# API client for registering public studies in DUOS

class DuosClient
  extend ServiceAccountManager
  include GoogleServiceClient
  include ApiHelpers

  attr_accessor :access_token, :api_root, :expires_at, :service_account_credentials

  GOOGLE_SCOPES = %w(openid email profile).freeze

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
  #   - +service_account_key+: (String, Pathname) => Path to service account JSON keyfile
  # * *return*
  #   - +DuosClient+ object
  def initialize(service_account = self.class.get_primary_keyfile)
    sub_host = Rails.env.production? ? 'prod' : 'dev'
    self.service_account_credentials = service_account
    self.access_token = self.class.generate_access_token(service_account)
    self.expires_at = Time.zone.now + self.access_token['expires_in']
    self.api_root = "https://consent.dsde-#{sub_host}.broadinstitute.org"
  end

  # submit a request to DUOS API
  #
  # * *params*
  #   - +http_method+ (String, Symbol) => HTTP method, e.g. :get, :post
  #   - +path+ (String) => Relative URL path for API request being made
  #   - +payload+ (Hash) => request body
  #   - +retry_count+ (Integer) => Counter for tracking request retries
  #
  # * *returns*
  #   - (Hash) => Parsed response body, if present
  #
  # * *raises*
  #   - (RestClient::Exception) => if HTTP request fails for any reason
  def process_api_request(http_method, path, payload: nil, retry_count: 0)
    # Log API call for auditing/tracking purposes
    Rails.logger.info "DUOS API request (#{http_method.to_s.upcase}) #{path}"
    # process request
    begin
      execute_http_request(http_method, path, payload)
    rescue RestClient::Exception => e
      current_retry = retry_count + 1
      context = " encountered when requesting '#{path}', attempt ##{current_retry}"
      log_message = "#{e.message}: #{e.http_body}; #{context}"
      Rails.logger.error log_message
      if should_retry?(e.http_code) && retry_count < ApiHelpers::MAX_RETRY_COUNT
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
    url = [api_root, path].join('/')
    headers = headers_for_request(multipart: payload.present?)
    response = RestClient::Request.execute(method: http_method, url:, payload:, headers:)
    handle_response(response)
  end

  # API endpoints

  # basic health check
  #
  # * *returns*
  #   - (Boolean) => T/F if NeMO is responding to requests
  def api_available?
    path = 'status'
    begin
      status = execute_http_request(:get, path)&.with_indifferent_access
      status && status[:ok]
    rescue RestClient::ExceptionWithResponse => e
      Rails.logger.error "DUOS service unavailable: #{e.message}"
      ErrorTracker.report_exception(e, nil, { method: :get, url: path, code: e.http_code })
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
  def create_dataset(study)
    study_data = schema_from(study)
    api_path = 'api/dataset/v3'
    process_api_request(:post, api_path, payload: study_data.to_json)
  end

  # update a DUOS dataset using an SCP study
  #
  # * *params*
  #   - +study+ (Study)
  #   - +fields+ (Array<Hash<) array of key/value pairs to update in DUOS
  #              see https://consent.dsde-dev.broadinstitute.org/#/Dataset/put_api_dataset_v3__datasetId_
  #
  # * *returns*
  #   - (Hash) DUOS dataset registration of updated study
  #
  # * *raises*
  #   - (ArgumentError) if study is not registered in DUOS
  def update_dataset(study, **fields)
    raise ArgumentError, "#{study.accession} has no DUOS dataset ID" if study.duos_dataset_id.blank?

    study_data = update_schema_from(study, **fields)
    api_path = "api/dataset/v3/#{study.duos_dataset_id}"
    process_api_request(:put, api_path, payload: study_data.to_json)
  end

  # delete a dataset in DUOS for non-production endpoints
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Boolean)
  def delete_dataset(study)
    return false if Rails.env.production? || study.duos_dataset_id.blank?

    api_path = "api/dataset/#{study.duos_dataset_id}"
    process_api_request(:delete, api_path)
  end

  # handle a study redaction
  # in production, set to publicVisibility to false
  # otherwise delete the study
  def redact_dataset(study)
    if Rails.env.production?
      update_dataset(study, publicVisibility: false)
    else
      delete_dataset(study)
    end
  end

  # register service account with DUOS
  #
  # * *returns*
  #   - (Hash) SAM user registration of service account
  def register
    api_path = 'api/user'
    process_api_request(:post, api_path)
  end

  # retrieve DUOS registration for service account
  #
  # * *returns*
  #   - (Hash) SAM user registration of service account
  def registration
    api_path = 'api/user/me'
    process_api_request(:get, api_path)
  end

  # check if a client is registered
  #
  # *returns*
  #  - (Boolean)
  def registered?
    api_path = 'api/user/me'
    registration = execute_http_request(:get, api_path)&.with_indifferent_access
    registration && registration[:userId].present?
  rescue RestClient::ExceptionWithResponse
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
    api_path = 'api/sam/register/self/diagnostics'
    status = execute_http_request(:get, api_path)&.with_indifferent_access
    status && status[:tosAccepted]
  rescue RestClient::ExceptionWithResponse
    false
  end

  # monkey-patch of issuer method since we're not loading the GCS SDK
  #
  # * *returns*
  #  - (String) service account email
  def issuer
    self.class.load_service_account_creds(service_account_credentials)&.issuer
  end

  # construct a DUOS schema object for registering a dataset
  # from https://consent.dsde-prod.broadinstitute.org/#/Schema/getDatasetRegistrationSchemaV1
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Hash) => DUOS dataset schema object
  def schema_from(study)
    consent_values = CONSENT_VALUES.merge(
      consentGroupName: duos_study_name(study), numberOfParticipants: study.donor_count, url: study.study_url
    )
    dataset = {
      studyName: duos_study_name(study),
      studyDescription: duos_study_description(study),
      dataTypes: study.data_types,
      publicVisibility: study.public,
      phenotypeIndication: study.diseases.join(', '),
      species: study.species_list.join(', '),
      dataCustodianEmail: study.data_custodians,
      consentGroups: consent_values
    }.merge(ANVIL_VALUES)
    { dataset: }.with_indifferent_access
  end

  # construct and update schema object with a list of fields to modify
  #
  # * *params*
  #   - +study+ (Study)
  #   - +fields+ (Hash) multiple key/value pairs of field names to values to update
  #
  # * *returns*
  #   - (Hash) => DUOS dataset update schema object
  def update_schema_from(study, **fields)
    dataset = {
      studyName: duos_study_name(study),
      dacId: study.duos_dataset_id,
      properties: fields.map do |field_name, value|
        { propertyName: field_name.to_s, propertyValue: value }
      end
    }
    { dataset: }.with_indifferent_access
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
