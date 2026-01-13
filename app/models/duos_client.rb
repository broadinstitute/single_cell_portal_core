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

  # initialize new client and generate access token for auth
  #
  # * *params*
  #   - +service_account_key+: (String, Pathname) => Path to service account JSON keyfile
  # * *return*
  #   - +DuosClient+ object
  def initialize(service_account = self.class.get_read_only_keyfile)
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
                                      }
        )
        error_message = parse_response_body(e.message)
        Rails.logger.error "Retry count exceeded when requesting '#{path}' - #{error_message}"
        raise e
      end
    end
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
    response = RestClient::Request.execute(method: http_method, url: path, payload:, headers: get_default_headers)
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
      status && status[:ok]
    rescue RestClient::ExceptionWithResponse => e
      Rails.logger.error "DUOS service unavailable: #{e.message}"
      ErrorTracker.report_exception(e, nil, { method: :get, url: path, code: e.http_code })
      false
    end
  end

  def register_study(study)
    study_data = schema_from(study)
    api_path = '/api/dataset/v3'
    process_api_request(:post, api_path, payload: study_data)
  end

  def update_study(study, **fields)
    study_data = update_schema_from(study, **fields)
    api_path = '/api/dataset/v3'
    process_api_request(:put, api_path, payload: study_data)
  end

  # delete a dataset in DUOS for non-production endpoints
  def delete_study(study)
    return false if Rails.env.production? || study.duos_dataset_id.blank?

    api_path = "/api/dataset/#{study.duos_dataset_id}"
    process_api_request(:delete, api_path)
  end

  # handle a study redaction (production, set to private, otherwise delete the study)
  def redact_study(study)
    if Rails.env.production?
      update_study(study, publicVisibility: false)
    else
      delete_study(study)
    end
  end

  # register service account with DUOS
  def register
    api_path = '/api/user'
    process_api_request(:post, api_path)
  end

  # retrieve DUOS registration for service account
  def registration
    api_path = '/api/user/me'
    process_api_request(:get, api_path)
  end

  # accept DUOS terms of service for service account
  def accept_tos
    api_path = '/api/sam/register/self/tos'
    process_api_request(:post, api_path)
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
      consentGroupName: formatted_study_name(study), numberOfParticipants: study.donor_count, url: study.study_url
    )
    {
      studyName: formatted_study_name(study),
      studyDescription: "#{study.description} (Platform: Single Cell Portal)",
      dataTypes: study.data_types,
      publicVisibility: study.public,
      phenotypeIndication: study.diseases.join(', '),
      species: study.species_list.join(', '),
      dataCustodianEmail: study.data_custodians,
      consentGroups: consent_values
    }.merge(ANVIL_VALUES).with_indifferent_access
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
    {
      studyName: formatted_study_name(study),
      dacId: study.duos_dataset_id,
      properties: fields.map do |field_name, value|
        { propertyName: field_name.to_s, propertyValue: value }
      end
    }.with_indifferent_access
  end

  # version of study name with accession prepended
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (String)
  def formatted_study_name(study)
    "#{study.accession} - #{study.name}"
  end
end
