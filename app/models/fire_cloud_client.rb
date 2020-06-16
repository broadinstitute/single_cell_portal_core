##
# FireCloudClient: Class that wraps API calls to both FireCloud and Google Cloud Storage to manage the CRUDing of both
# FireCloud workspaces and files inside the associated GCP storage buckets, as well as billing/user group/workflow submission
# management.
#
# Uses the gems googleauth (for generating access tokens), google-cloud-storage (for bucket/file access),
# and rest-client (for HTTP calls)
#
# Author::  Jon Bistline  (mailto:bistline@broadinstitute.org)

class FireCloudClient < Struct.new(:user, :project, :access_token, :api_root, :storage, :expires_at, :service_account_credentials)

  extend ErrorTracker

  #
  # CONSTANTS
  #

  # base url for all API calls
  BASE_URL = 'https://api.firecloud.org'
  # default auth scopes
  GOOGLE_SCOPES = %w(https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/cloud-billing.readonly https://www.googleapis.com/auth/devstorage.read_only)
  # constant used for retry loops in process_firecloud_request and execute_gcloud_method
  MAX_RETRY_COUNT = 5
  # constant used for incremental backoffs on retries (in seconds); ignored when running unit/integration test suite
  RETRY_INTERVAL = Rails.env == 'test' ? 0 : 15
  # List of URLs/Method names to never retry on or report error, regardless of error state
  ERROR_IGNORE_LIST = ["#{BASE_URL}/register"]
  # List of URLs/Method names to ignore incremental backoffs on (in cases of UI blocking)
  RETRY_BACKOFF_BLACKLIST = ["#{BASE_URL}/register", :generate_signed_url, :generate_api_url]
  # default namespace used for all FireCloud workspaces owned by the 'portal'
  PORTAL_NAMESPACE = ENV['PORTAL_NAMESPACE'].present? ? ENV['PORTAL_NAMESPACE'] : 'single-cell-portal'
  # location of Google service account JSON (must be absolute path to file)
  SERVICE_ACCOUNT_KEY = !ENV['SERVICE_ACCOUNT_KEY'].blank? ? File.absolute_path(ENV['SERVICE_ACCOUNT_KEY']) : ''
  # location of Google service account JSON (must be absolute path to file)
  READ_ONLY_SERVICE_ACCOUNT_KEY = !ENV['READ_ONLY_SERVICE_ACCOUNT_KEY'].blank? ? File.absolute_path(ENV['READ_ONLY_SERVICE_ACCOUNT_KEY']) : ''
  # Permission values allowed for FireCloud workspace ACLs
  WORKSPACE_PERMISSIONS = ['OWNER', 'READER', 'WRITER', 'NO ACCESS']
  # List of FireCloud user group roles
  USER_GROUP_ROLES = %w(admin member)
  # List of FireCloud billing project roles
  BILLING_PROJECT_ROLES = %w(user owner)
  # List of projects where computes are not permitted (sets canCompute to false for all users by default, can only be overridden
  # by PROJECT_OWNER)
  COMPUTE_BLACKLIST = %w(single-cell-portal)
  # Name of user group to set as workspace owner for user-controlled billing projects.  Reduces the amount of
  # groups the portal service account needs to be a member of
  # defaults to the Terra billing project this instance is configured against, plus "-sa-owner-group"
  WS_OWNER_GROUP_NAME = "#{PORTAL_NAMESPACE}-sa-owner-group"

  ##
  # SERVICE NAMES AND DESCRIPTIONS
  #
  # The following constants are named FireCloud "services" that cover various pieces of functionality that
  # SCP depends on.  These names are stored here to reduce duplication and prevent typos.
  # A list of all available service names can be retrieved with FireCloudClient#api_status
  ##

  # Rawls is the largest service that pertains to workspaces and pipeline submissions via the managed Cromwell instance
  # SCP uses Rawls for updating studies, uploading/parsing files, launching workflows
  RAWLS_SERVICE = 'Rawls'
  # SAM holds most of the workspace permissions and other features
  # SCP uses Sam for updating studies, uploading/parsing files
  SAM_SERVICE = 'Sam'
  # Agora covers the Methods repository and other analysis-oriented features
  # SCP uses Agora for configuring new analyses, submitting workflows
  AGORA_SERVICE = 'Agora'
  # Thurloe covers Terra profiles and billing projects
  # SCP uses Thurloe for managing user's Terra profiles and billing projects
  THURLOE_SERVICE = 'Thurloe'
  # Workspaces come with GCP buckets, and the GoogleBuckets service helps manage permissions
  # SCP requires GoogleBuckets to be up for uploading/downloading files, even though SCP uses the GCS JSON API directly
  # via the google-cloud-storage gem.
  BUCKETS_SERVICE = 'GoogleBuckets'

  ##
  # METHODS
  ##

  # initialize is called after instantiating with FireCloudClient.new
  # will set the access token, FireCloud api url root and GCP storage driver instance
  #
  # * *params*
  #   - +user+: (User) => User object from which access tokens are generated
  #   - +project+: (String) => Default GCP Project to use (can be overridden by other parameters)
  # * *return*
  #   - +FireCloudClient+ object
  def initialize(user=nil, project=nil, service_account=SERVICE_ACCOUNT_KEY)
    # when initializing without a user, default to base configuration
    if user.nil?
      # instantiate Google Cloud Storage driver to work with files in workspace buckets
      # if no keyfile is present, use environment variables
      storage_attr = {
          project: PORTAL_NAMESPACE,
          timeout: 3600
      }

      if !service_account.blank?
        storage_attr.merge!(keyfile: service_account)
        self.service_account_credentials = service_account
      end

      self.access_token = FireCloudClient.generate_access_token(service_account)
      self.project = PORTAL_NAMESPACE

      self.storage = Google::Cloud::Storage.new(storage_attr)

      # set expiration date of token
      self.expires_at = Time.zone.now + self.access_token['expires_in']
    else
      self.user = user
      self.project = project
      # user.token_for_api_call will retrieve valid access token to use, if present
      self.access_token = user.token_for_api_call
      self.expires_at = self.access_token['expires_at']

      # use user-defined project instead of portal default
      # if no keyfile is present, use environment variables
      storage_attr = {
          project: project,
          timeout: 3600
      }

      if !service_account.blank?
        storage_attr.merge!(keyfile: service_account)
        self.service_account_credentials = service_account
      end

      self.storage = Google::Cloud::Storage.new(storage_attr)
    end
    # set FireCloud API base url
    self.api_root = BASE_URL
  end

  # return a hash of instance attributes for this client
  #
  # * *return*
  #   - +Hash+ of values for all instance variables for this client
  def attributes
    sanitized_values = self.to_h.dup
    sanitized_values[:access_token] = 'REDACTED'
    sanitized_values[:issuer] = self.issuer
    sanitized_values
  end

  #
  # TOKEN METHODS
  #

  # generate an access token to use for all requests
  #
  # * *return*
  #   - +Hash+ of Google Auth access token (contains access_token (string), token_type (string) and expires_in (integer, in seconds)
  def self.generate_access_token(service_account)
    # if no keyfile present, use environment variables
    creds_attr = {scope: GOOGLE_SCOPES}
    if !service_account.blank?
      creds_attr.merge!(json_key_io: File.open(service_account))
    end
    creds = Google::Auth::ServiceAccountCredentials.make_creds(creds_attr)
    token = creds.fetch_access_token!
    token
  end

  # refresh access_token when expired and stores back in FireCloudClient instance
  #
  # * *return*
  #   - +DateTime+ timestamp of new access token expiration
  def refresh_access_token
    if self.user.nil?
      new_token = FireCloudClient.generate_access_token(self.service_account_credentials)
      new_expiry = Time.zone.now + new_token['expires_in']
      self.access_token = new_token
      self.expires_at = new_expiry
    else
      new_token = self.user.generate_access_token
      self.access_token = new_token
      self.expires_at = new_token['expires_at']
    end
    new_token
  end

  # check if an access_token is expired
  #
  # * *return*
  #   - +Boolean+ of token expiration
  def access_token_expired?
    Time.zone.now >= self.expires_at
  end

  # return a valid access token
  #
  # * *return*
  #   - +Hash+ of access token
  def valid_access_token
    self.access_token_expired? ? self.refresh_access_token : self.access_token
  end

  ##
  ## STORAGE INSTANCE METHODS
  ##

  # get instance information about the storage driver
  #
  # * *return*
  #   - +JSON+ object of storage driver instance attributes
  def storage_attributes
    JSON.parse self.storage.to_json
  end

  # renew the storage driver
  #
  # * *params*
  #   - +project_name+ (String )=> name of GCP project, default project is value of PORTAL_NAMESPACE
  #
  # * *return*
  #   - +Google::Cloud::Storage+ instance
  def refresh_storage_driver(project_name=PORTAL_NAMESPACE)
    storage_attr = {
        project: project_name,
        timeout: 3600
    }
    if !ENV['SERVICE_ACCOUNT_KEY'].blank?
      storage_attr.merge!(keyfile: SERVICE_ACCOUNT_KEY)
    end
    new_storage = Google::Cloud::Storage.new(storage_attr)
    self.storage = new_storage
    new_storage
  end

  # get storage driver access token
  #
  # * *return*
  #   - +String+ access token
  def storage_access_token
    self.storage.service.credentials.client.access_token
  end

  # get storage driver issue timestamp
  #
  # * *return*
  #   - +DateTime+ issue timestamp
  def storage_issued_at
    self.storage.service.credentials.client.issued_at
  end

  # get issuer of storage credentials
  #
  # * *return*
  #   - +String+ of issuer email
  def storage_issuer
    self.storage.service.credentials.issuer
  end

  # get issuer of access_token
  #
  # * *return*
  #   - +String+ of access_token issuer email
  def issuer
    self.user.nil? ? self.storage_issuer : self.user.email
  end

  # get issuer object of access_token (either instance of User, or email of service account)
  #
  # * *return*
  #   - +User+ of access_token issuer or +String+ of service account email
  def issuer_object
    self.user.nil? ? self.storage_issuer : self.user
  end

  # identify user initiating a request; either self.user, Current.user, or service account
  #
  # *return*
  #   - +String+ db identifier of user, or service account email
  def tracking_identifier
    if self.user.present?
      self.user.id
    elsif Current.user.present?
      Current.user.id
    else
      self.issuer
    end
  end

  ######
  ##
  ## FIRECLOUD METHODS
  ##
  ######

  # generic handler to execute http calls, process returned JSON and handle exceptions
  #
  # * *params*
  #   - +http_method+ (String, Symbol) => valid http method
  #   - +path+ (String) => FireCloud REST API path
  #   - +payload+ (Hash) => HTTP POST/PATCH/PUT body for creates/updates, defaults to nil
  #		- +opts+ (Hash) => Hash of extra options (defaults are file_upload=false, max_attemps=MAX_RETRY_COUNT)
  #   - +retry_count+ (Integer) => current count of number of retries.  defaults to 0 and self-increments
  #
  # * *return*
  #   - +Hash+, +Boolean+ depending on response body
  # * *raises*
  #   - +RuntimeError+
  def process_firecloud_request(http_method, path, payload=nil, opts={}, retry_count=0)
    # set up default options
    request_opts = {file_upload: false}.merge(opts)

    # Log API call for auditing/tracking purposes
    Rails.logger.info "FireCloud API request (#{http_method.to_s.upcase}) #{path} with tracking identifier: #{self.tracking_identifier}"
    # check for token expiry first before executing
    if self.access_token_expired?
      Rails.logger.info "FireCloudClient token expired, refreshing access token"
      self.refresh_access_token
    end
    # set default headers, appending application identifier including hostname for disambiguation
    headers = {
        'Authorization' => "Bearer #{self.access_token['access_token']}",
        'x-app-id' => "single-cell-portal",
        'x-domain-id' => "#{ENV['HOSTNAME']}",
        'x-user-id' => "#{self.tracking_identifier}"
    }
    # if not uploading a file, set the content_type to application/json
    if !request_opts[:file_upload]
      headers.merge!({'Content-Type' => 'application/json'})
    end

    # process request
    begin
      response = RestClient::Request.execute(method: http_method, url: path, payload: payload, headers: headers)
      # handle response using helper
      handle_response(response)
    rescue RestClient::Exception => e
      current_retry = retry_count + 1
      context = " encountered when requesting '#{path}', attempt ##{current_retry}"
      log_message = e.message + ': ' + e.http_body + '; ' + context
      Rails.logger.error log_message
      retry_time = retry_count * RETRY_INTERVAL
      sleep(retry_time) unless RETRY_BACKOFF_BLACKLIST.include?(path) # only sleep if non-blocking
      # only retry if status code indicates a possible temporary error, and we are under the retry limit and
      # not calling a method that is blocked from retries
      if should_retry?(e.http_code) && retry_count < MAX_RETRY_COUNT && !ERROR_IGNORE_LIST.include?(path)
        process_firecloud_request(http_method, path, payload, opts, current_retry)
      else
        # we have reached our retry limit or the response code indicates we should not retry
        unless ERROR_IGNORE_LIST.include?(path)
          ErrorTracker.report_exception(e, self.issuer_object, {method: http_method, url: path, payload: payload,
                                                                opts: opts, retry_count: retry_count})
        end
        error_message = parse_error_message(e)
        Rails.logger.error "Retry count exceeded when requesting '#{path}' - #{error_message}"
        raise RuntimeError.new(error_message)
      end
    end
  end

  ##
  ## API STATUS
  ##

  # determine if FireCloud api is currently up/available
  #
  # * *return*
  #   - +Boolean+ indication of FireCloud current root status
  def api_available?
    begin
      response = self.api_status
      if response.is_a?(Hash) && response['ok']
        true
      else
        false
      end
    rescue => e
      false
    end
  end

  # get more detailed status information about FireCloud api
  # this method doesn't use process_firecloud_request as we want to preserve error states rather than catch and suppress them
  #
  # * *return*
  #   - +Hash+ with health status information for various FireCloud services or error response
  def api_status
    path = self.api_root + '/status'
    # make sure access token is still valid
    headers = {
        'Authorization' => "Bearer #{self.valid_access_token['access_token']}",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
    }
    begin
      response = RestClient::Request.execute(method: :get, url: path, headers: headers)
      JSON.parse(response.body)
    rescue RestClient::ExceptionWithResponse => e
      Rails.logger.error "FireCloud status error: #{e.message}"
      e.response
    end
  end

  # get health check on individual FireCloud services by name from FireCloudClient#api_status
  # Should not be used to assess overall API health, but rather a quick thumbs up/down on a specific service
  #
  # * *params*
  #   #   - +services+ (Array) => array of service names (from api_status['systems']), passed with splat operator, so should not be an actual array
  # * *return*
  #   - +Boolean+ indication of availability of requested FireCloud service
  def services_available?(*services)
    api_status = self.api_status
    if api_status.is_a?(Hash)
      api_ok = true
      services.each do |service|
        if api_status['systems'].present? && api_status['systems'][service].present? && api_status['systems'][service]['ok']
          next
        else
          api_ok = false
          break
        end
      end
      api_ok
    else
      false
    end
  end

  ##
  ## WORKSPACE METHODS
  ##

  # return a list of all workspaces in a given namespace
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #
  # * *return*
  #   - +Array+ of +Hash+ objects detailing workspaces
  def workspaces(workspace_namespace)
    path = self.api_root + '/api/workspaces'
    workspaces = process_firecloud_request(:get, path)
    workspaces.keep_if {|ws| ws['workspace']['namespace'] == workspace_namespace}
  end

  # create a workspace, prepending WORKSPACE_NAME_PREFIX as necessary
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of workspace
  #
  # * *return*
  #   - +Hash+ object of workspace instance
  def create_workspace(workspace_namespace, workspace_name, *authorization_domains)
    path = self.api_root + '/api/workspaces'
    # construct payload for POST
    payload = {
        namespace: workspace_namespace,
        name: workspace_name,
        attributes: {},
        authorizationDomain: []
    }
    # add authorization domains to new workspace
    authorization_domains.each do |domain|
      payload[:authorizationDomain] << {membersGroupName: domain}
    end
    process_firecloud_request(:post, path, payload.to_json)
  end

  # get the specified workspace
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of workspace
  #
  # * *return*
  #   - +Hash+ object of workspace instance
  def get_workspace(workspace_namespace, workspace_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}"
    process_firecloud_request(:get, path)
  end

  # delete a workspace
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of workspace
  #
  # * *return*
  #   - +Hash+ message of status of workspace deletion
  def delete_workspace(workspace_namespace, workspace_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}"
    process_firecloud_request(:delete, path)
  end

  # get the specified workspace ACL
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of workspace
  #
  # * *return*
  #   - +Hash+ object of workspace ACL instance
  def get_workspace_acl(workspace_namespace, workspace_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/acl"
    process_firecloud_request(:get, path)
  end

  # update the specified workspace ACL
  # can also be used to remove access by passing 'NO ACCESS' to create_acl
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of workspace
  #   - +acl+ (JSON) => ACL object (see create_workspace_acl)
  #
  # * *return*
  #   - +Hash+ response of ACL update
  def update_workspace_acl(workspace_namespace, workspace_name, acl)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/acl?inviteUsersNotFound=true"
    process_firecloud_request(:patch, path, acl)
  end

  # helper for creating FireCloud ACL objects
  # will raise a RuntimeError if permission requested does not match allowed values in WORKSPACE_PERMISSONS
  #
  # * *params*
  #   - +email+ (String) => email of FireCloud user
  #   - +permission+ (String) => granted permission level
  #   - +share_permission+ (Boolean) => whether or not user can share workspace
  #   - +compute_permission+ (Boolean) => whether or not user can run computes in workspace
  #
  # * *return*
  #   - +JSON+ ACL object
  def create_workspace_acl(email, permission, share_permission=true, compute_permission=false)
    if WORKSPACE_PERMISSIONS.include?(permission)
      [
          {
              'email' => email,
              'accessLevel' => permission,
              'canShare' => share_permission,
              'canCompute' => compute_permission
          }
      ].to_json
    else
      raise RuntimeError.new("Invalid FireCloud ACL permission setting: #{permission}; must be member of #{WORKSPACE_PERMISSIONS.join(', ')}")
    end
  end

  # set attributes for the specified workspace (will delete all existing attributes and overwrite with provided info)
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of workspace
  #   - +attributes+ (Hash) => Hash of workspace attributes (description, tags (Array), key/value pairs of other attributes)
  #
  # * *return*
  #   - +Hash+ object of workspace
  def set_workspace_attributes(workspace_namespace, workspace_name, attributes)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/setAttributes"
    process_firecloud_request(:patch, path, attributes.to_json)
  end

  # get the current storage cost estimate for a workspace
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of workspace
  #
  # * *return*
  #   - +Hash+ object of workspace
  def get_workspace_storage_cost(workspace_namespace, workspace_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/storageCostEstimate"
    process_firecloud_request(:get, path)
  end

  ##
  ## WORKFLOW SUBMISSION METHODS
  ##

  # get list of available FireCloud methods
  #
  # * *params*
  #   - +opts+ (Hash) => hash of query parameter key/value pairs, see https://api.firecloud.org/#!/Method_Repository/listMethodRepositoryMethods for complete list
  #
  # * *return*
  #   - +Array+ of methods
  def get_methods(opts={})
    query_params = self.merge_query_options(opts)
    path = self.api_root + "/api/methods#{query_params}"
    process_firecloud_request(:get, path)
  end

  # get a FireCloud method object
  #
  # * *params*
  #   - +namespace+ (String) => namespace of method
  #   - +name+ (String) => name of method
  #   - +snapshot_id+ (Integer) => snapshot ID of method
  #   - +only_payload+ (Boolean) => boolean of whether or not to return only the payload object
  #
  # * *return*
  #   - +Hash+ method object
  def get_method(namespace, method_name, snapshot_id, only_payload=false)
    path = self.api_root + "/api/methods/#{namespace}/#{method_name}/#{snapshot_id}?onlyPayload=#{only_payload}"
    process_firecloud_request(:get, path)
  end

  # get all configurations for a FireCloud method object
  #
  # * *params*
  #   - +namespace+ (String) => namespace of method
  #   - +name+ (String) => name of method
  #   - +snapshot_id+ (Integer) => snapshot ID of method
  #
  # * *return*
  #   - +Hash+ method object
  def get_method_configurations(namespace, method_name, snapshot_id)
    path = self.api_root + "/api/methods/#{namespace}/#{method_name}/#{snapshot_id}/configurations"
    process_firecloud_request(:get, path)
  end

  # get a FireCloud method input/output parameters
  #
  # * *params*
  #   - +namespace+ (String) => namespace of method
  #   - +name+ (String) => name of method
  #   - +snapshot_id+ (Integer) => snapshot ID of method
  #
  # * *return*
  #   - +Hash+ method object
  def get_method_parameters(namespace, method_name, snapshot_id)
    path = self.api_root + '/api/inputsOutputs'
    method_payload = {
        methodNamespace: namespace,
        methodName: method_name,
        methodVersion: snapshot_id
    }.to_json
    process_firecloud_request(:post, path, method_payload)
  end

  # get list of available configurations from the repository
  #
  # * *params*
  #   - +opts+ (Hash) => hash of query parameter key/value pairs, see https://api.firecloud.org/#!/Method_Repository/listMethodRepositoryConfigurations for complete list
  #
  # * *return*
  #   - +Array+ of configurations
  def get_configurations(opts={})
    query_params = self.merge_query_options(opts)
    path = self.api_root + "/api/configurations#{query_params}"
    process_firecloud_request(:get, path)
  end

  # get a FireCloud method configuration from the repository
  #
  # * *params*
  #   - +namespace+ (String) => namespace of method
  #   - +name+ (String) => name of configuration
  #   - +snapshot_id+ (Integer) => snapshot ID of method
  #   - +payload_as_object+ (Boolean) => Instead of returning a string under key payload, return a JSON object under key payloadObject
  #
  # * *return*
  #   - +Hash+ configuration object
  def get_configuration(namespace, name, snapshot_id, payload_as_object=false)
    path = self.api_root + "/api/configurations/#{namespace}/#{name}/#{snapshot_id}?payloadAsObject=#{payload_as_object}"
    process_firecloud_request(:get, path)
  end

  # copy a FireCloud method configuration from the repository into a workspace
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of workspace
  #   - +config_namespace+ (String) => namespace of source configuration
  #   - +config_name+ (String) => name of source configuration
  #   - +snapshot_id+ (Integer) => snapshot ID of source configuration
  #   - +destination_namespace+ (String) => namespace of destination configuration (in workspace)
  #   - +destination_name+ (String) => name of destination configuration (in workspace)
  #
  # * *return*
  #   - +Hash+ configuration object
  def copy_configuration_to_workspace(workspace_namespace, workspace_name, config_namespace, config_name, snapshot_id, destination_namespace, destination_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/method_configs/copyFromMethodRepo"
    payload = {
        configurationNamespace: config_namespace,
        configurationName: config_name,
        configurationSnapshotId: snapshot_id,
        destinationNamespace: destination_namespace,
        destinationName: destination_name
    }.to_json
    process_firecloud_request(:post, path, payload)
  end

  # create a method configuration template from a method
  #
  # * *params*
  #   - +method_namespace+ (String) => namespace of method
  #   - +method_name+ (String) => name of method
  #   - +method_version+ (String) => version of method
  #
  # * *return*
  #   - +Hash+ method configuration template
  def create_configuration_template(method_namespace, method_name, method_version)
    path = self.api_root + '/api/template'
    payload = {
        methodNamespace: method_namespace,
        methodName: method_name,
        methodVersion: method_version
    }.to_json
    process_firecloud_request(:post, path, payload)
  end

  # get a list of FireCloud method configurations in a specified workspace
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #
  # * *return*
  #   - +Array+ of configuration objects
  def get_workspace_configurations(workspace_namespace, workspace_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/methodconfigs"
    process_firecloud_request(:get, path)
  end

  # get a FireCloud method configuration from a workspace
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +config_namespace+ (String) => namespace of configuration
  #   - +config_name+ (String) => name of configuration
  #
  # * *return*
  #   - +Hash+ configuration object
  def get_workspace_configuration(workspace_namespace, workspace_name, config_namespace, config_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/method_configs/#{config_namespace}/#{config_name}"
    process_firecloud_request(:get, path)
  end

  # create a FireCloud method configuration in a workspace from a template or existing configuration
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #		- +configuration+ (Hash) => configuration object (see https://api.firecloud.org/#!/Method_Configurations/updateWorkspaceMethodConfig for more info)
  #
  # * *return*
  #   - +Hash+ configuration object
  def create_workspace_configuration(workspace_namespace, workspace_name, configuration)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/methodconfigs"
    process_firecloud_request(:post, path, configuration.to_json)
  end

  # update a FireCloud method configuration in a workspace
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +config_namespace+ (String) => namespace of configuration
  #   - +config_name+ (String) => name of configuration
  #		- +configuration+ (Hash) => configuration object (see https://api.firecloud.org/#!/Method_Configurations/updateWorkspaceMethodConfig for more info)
  #
  # * *return*
  #   - +Hash+ configuration object
  def update_workspace_configuration(workspace_namespace, workspace_name, config_namespace, config_name, configuration)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/method_configs/#{config_namespace}/#{config_name}"
    process_firecloud_request(:post, path, configuration.to_json)
  end

  # overwrite an existing FireCloud method configuration in a workspace
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +config_namespace+ (String) => namespace of configuration
  #   - +config_name+ (String) => name of configuration
  #		- +configuration+ (Hash) => configuration object (see https://api.firecloud.org/#!/Method_Configurations/overwriteWorkspaceMethodConfig for more info)
  #
  # * *return*
  #   - +Hash+ configuration object
  def overwrite_workspace_configuration(workspace_namespace, workspace_name, config_namespace, config_name, configuration)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/method_configs/#{config_namespace}/#{config_name}"
    process_firecloud_request(:put, path, configuration.to_json)
  end

  # get submission queue status
  #
  # * *return*
  #   - +Hash+ object of current submission queue status
  def get_submission_queue_status
    path = self.api_root + '/api/submissions/queueStatus'
    process_firecloud_request(:get, path)
  end

  # get a list of workspace workflow queue submissions
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #
  # * *return*
  #   - +Array+ of workflow submissions
  def get_workspace_submissions(workspace_namespace, workspace_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/submissions"
    process_firecloud_request(:get, path)
  end

  # validate a workflow submission before submitting
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +config_namespace+ (String) => namespace of requested configuration
  #   - +config_name+ (String) => name of requested configuration
  #   - +entity_type+ (String) => type of workspace entity (e.g. sample, participant, etc)
  #   - +entity_name+ (String) => name of workspace entity
  #
  # * *return*
  #   - +Hash+ of workflow submission details
  def validate_workspace_submission(workspace_namespace, workspace_name, config_namespace, config_name, entity_type, entity_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/submissions/validate"
    submission = {
        methodConfigurationNamespace: config_namespace,
        methodConfigurationName: config_name,
        entityType: entity_type,
        entityName: entity_name,
        useCallCache: true,
        workflowFailureMode: 'NoNewCalls'
    }.to_json

    process_firecloud_request(:post, path, submission)
  end

  # create a workflow submission
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +config_namespace+ (String) => namespace of requested configuration
  #   - +config_name+ (String) => name of requested configuration
  #   - +entity_type+ (String) => type of workspace entity (e.g. sample, participant, etc)
  #   - +entity_name+ (String) => name of workspace entity
  #
  # * *return*
  #   - +Hash+ of workflow submission details
  def create_workspace_submission(workspace_namespace, workspace_name, config_namespace, config_name, entity_type, entity_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/submissions"
    submission = {
        methodConfigurationNamespace: config_namespace,
        methodConfigurationName: config_name,
        entityType: entity_type,
        entityName: entity_name,
        useCallCache: true,
        workflowFailureMode: 'NoNewCalls'
    }.to_json
    process_firecloud_request(:post, path, submission)
  end

  # get a single workflow submission
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +submission_id+ (String) => id of requested submission
  #
  # * *return*
  #   - +Hash+ workflow submission object
  def get_workspace_submission(workspace_namespace, workspace_name, submission_id)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/submissions/#{submission_id}"
    process_firecloud_request(:get, path)
  end

  # abort a workflow submission
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +submission_id+ (Integer) => ID of workflow submission
  #
  # * *return*
  #   - +Boolean+ indication of workflow cancellation
  def abort_workspace_submission(workspace_namespace, workspace_name, submission_id)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/submissions/#{submission_id}"
    process_firecloud_request(:delete, path)
  end

  # get call-level metadata from a single workflow submission workflow instance
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +submission_id+ (String) => id of requested submission
  #   - +workflow_id+ (String) => id of requested workflow
  #
  # * *return*
  #   - +Hash+ of workflow object
  def get_workspace_submission_workflow(workspace_namespace, workspace_name, submission_id, workflow_id)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/submissions/#{submission_id}/workflows/#{workflow_id}"
    process_firecloud_request(:get, path)
  end

  # get outputs from a single workflow submission workflow instance
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +submission_id+ (String) => id of requested submission
  #   - +workflow_id+ (String) => id of requested workflow
  #
  # * *return*
  #   - +Array+ of workflow submission outputs
  def get_workspace_submission_outputs(workspace_namespace, workspace_name, submission_id, workflow_id)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/submissions/#{submission_id}/workflows/#{workflow_id}/outputs"
    process_firecloud_request(:get, path)
  end

  # get permissions for a method configuration namespace
  #
  # * *params*
  #   - +config_namespace+ (String) => namespace of configuraiton
  #
  # * *return*
  #   - +Array+ of users & permission levels
  def get_config_namespace_permissions(config_namespace)
    path = self.api_root + "/api/configurations/#{config_namespace}/permissions"
    process_firecloud_request(:get, path)
  end

  # get permissions for a method configuration namespace
  #
  # * *params*
  #   - +config_namespace+ (String) => namespace of configuraiton
  #   - +permissions+ (Array) => Array of permission objects (Hash of user & role)
  #
  # * *return*
  #   - +Array+ of users & permission levels
  def update_config_namespace_permissions(config_namespace, permissions)
    path = self.api_root + "/api/configurations/#{config_namespace}/permissions"
    process_firecloud_request(:post, path, permissions.to_json)
  end

  # get permissions for a method namespace
  #
  # * *params*
  #   - +config_namespace+ (String) => namespace of configuraiton
  #
  # * *return*
  #   - +Array+ of users & permission levels
  def get_method_namespace_permissions(config_namespace)
    path = self.api_root + "/api/methods/#{config_namespace}/permissions"
    process_firecloud_request(:get, path)
  end

  # get permissions for a method namespace
  #
  # * *params*
  #   - +config_namespace+ (String) => namespace of configuraiton
  #   - +permissions+ (Array) => Array of permission objects (Hash of user & role)
  #
  # * *return*
  #   - +Array+ of users & permission levels
  def update_method_namespace_permissions(config_namespace, permissions)
    path = self.api_root + "/api/methods/#{config_namespace}/permissions"
    process_firecloud_request(:post, path, permissions.to_json)
  end

  ##
  ## WORKSPACE ENTITY METHODS
  ##

  # list workspace metadata entities with type and attribute information
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #
  # * *return*
  #   - +Array+ of workspace metadata entities with type and attribute information
  def get_workspace_entities(workspace_namespace, workspace_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/entities_with_type"
    process_firecloud_request(:get, path)
  end

  # list workspace metadata entity types
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #
  # * *return*
  #   - +Array+ of workspace metadata entities
  def get_workspace_entity_types(workspace_namespace, workspace_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/entities"
    process_firecloud_request(:get, path)
  end

  # get a list workspace metadata entities of requested type
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +entity_type+ (String) => type of requested entity
  #
  # * *return*
  #   - +Array+ of workspace metadata entities with type and attribute information
  def get_workspace_entities_by_type(workspace_namespace, workspace_name, entity_type)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/entities/#{entity_type}"
    process_firecloud_request(:get, path)
  end

  # get an individual workspace metadata entity
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +entity_type+ (String) => type of requested entity
  #   - +entity_name+ (String) => name of requested entity
  #
  # * *return*
  #   - +Array+ of workspace metadata entities with type and attribute information
  def get_workspace_entity(workspace_namespace, workspace_name, entity_type, entity_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/entities/#{entity_type}/#{entity_name}"
    process_firecloud_request(:get, path)
  end

  # update an individual workspace metadata entity
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +entity_type+ (String) => type of requested entity
  #   - +entity_name+ (String) => name of requested entity
  #   - +operation_type+ (String) => type of operation requested (add/update)
  #   - +attribute_name+ (String) => name of attribute being changed
  #   - +attribute_value+ (String) => value of attribute being changed
  #
  # * *return*
  #   - +Array+ of workspace metadata entities with type and attribute information
  def update_workspace_entity(workspace_namespace, workspace_name, entity_type, entity_name, operation_type, attribute_name, attribute_value)
    update = {
        op: operation_type,
        attributeName: attribute_name,
        addUpdateAttribute: attribute_value
    }.to_json
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/entities/#{entity_type}/#{entity_name}"
    process_firecloud_request(:patch, path, update)
  end

  # get a tsv file of requested workspace metadata entities of requested type
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +entity_type+ (String) => type of requested entity
  #   - +entity_names+ (String) => list of requested entities to include in file (provide each as a separate parameter)
  #
  # * *return*
  #   - +Array+ of workspace metadata entities with type and attribute information
  def get_workspace_entities_as_tsv(workspace_namespace, workspace_name, entity_type, *attribute_names)
    attribute_list = attribute_names.join(',')
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/entities/#{entity_type}/tsv#{attribute_list.blank? ? nil : '?attributeNames=' + attribute_list}"
    process_firecloud_request(:get, path)
  end

  # get a tsv file of requested workspace metadata entities of requested type
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +entities_file+ (File) => valid TSV import file of metadata entities (must be an open File handler)
  #
  # * *return*
  #   -  String of entity type that was just created
  def import_workspace_entities_file(workspace_namespace, workspace_name, entities_file)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/importEntities"
    entities_upload = {
        entities: entities_file
    }
    process_firecloud_request(:post, path, entities_upload, {file_upload: true})
  end

  # bulk delete workspace metadata entities
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +workspace_entities+ (Array of objects) => array of hashes mapping to workspace metadata entities
  #
  # * *return*
  #   - +Array+ of workspace metadata entities
  def delete_workspace_entities(workspace_namespace, workspace_name, workspace_entities)
    # validate entities first before making delete call
    valid_workspace_entities = []
    workspace_entities.each do |entity|
      if entity.keys.sort.map(&:to_s) == %w(entityName entityType) && entity.values.size == 2
        valid_workspace_entities << entity
      end
    end
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/entities/delete"
    process_firecloud_request(:post, path,  valid_workspace_entities.to_json)
  end

  ##
  ## USER GROUPS METHODS (only work when FireCloudClient is instantiated with a User account)
  ##

  # get a list of groups for a user
  #
  # * *return*
  #   - +Array+ of groups
  def get_user_groups
    path = self.api_root + "/api/groups"
    process_firecloud_request(:get, path)
  end

  # get a specific user group that the user belongs to
  #
  # * *params*
  #   - +group_name+ (String) => name of requested group
  #
  # * *return*
  #   - +Hash+ of group attributes
  def get_user_group(group_name)
    path = self.api_root + "/api/groups/#{group_name}"
    process_firecloud_request(:get, path)
  end

  # create a user group
  #
  # * *params*
  #   - +group_name+ (String) => name of requested group
  #
  # * *return*
  #   - +Hash+ of group attributes
  def create_user_group(group_name)
    path = self.api_root + "/api/groups/#{group_name}"
    process_firecloud_request(:post, path)
  end

  # delete a user group that a user owns
  #
  # * *params*
  #   - +group_name+ (String) => name of requested group
  #
  # * *return*
  #   - +Boolean+ indication of group delete
  def delete_user_group(group_name)
    path = self.api_root + "/api/groups/#{group_name}"
    process_firecloud_request(:delete, path)
  end

  # add another user to a user group the current user owns
  #
  # * *params*
  #   - +group_name+ (String) => name of requested group
  #   - +user_role+ (String) => role of user to add to group (must be member or admin)
  #   - +user_email+ (String) => email of user to add to group
  #
  # * *return*
  #   - +Boolean+ indication of user addition
  def add_user_to_group(group_name, user_role, user_email)
    if USER_GROUP_ROLES.include?(user_role)
      path = self.api_root + "/api/groups/#{group_name}/#{user_role}/#{user_email}"
      process_firecloud_request(:put, path)
    else
      raise RuntimeError.new("Invalid FireCloud user group role: #{user_role}; must be one of '#{USER_GROUP_ROLES.join(', ')}'")
    end
  end

  # remove another user to a user group the current user owns
  #
  # * *params*
  #   - +group_name+ (String) => name of requested group
  #   - +user_role+ (String) => role of user to add to group (must be member or admin)
  #   - +user_email+ (String) => email of user to add to group
  #
  # * *return*
  #   - +Boolean+ indication of user removal
  def delete_user_from_group(group_name, user_role, user_email)
    if USER_GROUP_ROLES.include?(user_role)
      path = self.api_root + "/api/groups/#{group_name}/#{user_role}/#{user_email}"
      process_firecloud_request(:delete, path)
    else
      raise RuntimeError.new("Invalid FireCloud user group role: #{user_role}; must be one of '#{USER_GROUP_ROLES.join(', ')}'")
    end
  end

  # request access to a user group as the current user
  #
  # * *params*
  #   - +group_name+ (String) => name of requested group
  #
  # * *return*
  #   - +Boolean+ indication of request submission
  def request_user_group(group_name)
    path = self.api_root + "/api/groups/#{group_name}/requestAccess"
    process_firecloud_request(:post, path)
  end

  ##
  ## PROFILE/BILLING METHODS
  ##

  # get a user's profile status
  #
  # * *return*
  #   - +Hash+ of user registration properties, including email, userID and enabled features
  def get_registration
    path = self.api_root + '/register'
    process_firecloud_request(:get, path)
  end

  # register a new user or update a user's profile in FireCloud
  #
  # * *params*
  #   - +profile_contents+ (Hash) => complete FireCloud profile information, see https://api.firecloud.org/#!/Profile/setProfile for details
  #
  # * *return*
  #   - +Hash+ of user's registration status information (see FireCloudClient#registration)
  def set_profile(profile_contents)
    path = self.api_root + '/register/profile'
    process_firecloud_request(:post, path, profile_contents.to_json)
  end

  # get a user's profile status
  #
  # * *return*
  #   - +Hash+ of key/value pairs of information stored in a user's FireCloud profile
  def get_profile
    path = self.api_root + '/register/profile'
    process_firecloud_request(:get, path)
  end

  # check if a user is registered (via access token)
  #
  # * *return*
  #   - +Boolean+ indication of whether or not user is registered
  def registered?
    begin
      self.get_registration
      true
    rescue => e
      # any error should be treated as the user not being registered
      false
    end
  end

  # list billing projects for a given user
  #
  # * *return*
  #   - +Array+ of Hashes of billing projects
  def get_billing_projects
    path = self.api_root + '/api/profile/billing'
    process_firecloud_request(:get, path)
  end

  # list billing accounts for a given user
  #
  # * *return*
  #   - +Array+ of Hashes of billing accounts
  def get_billing_accounts
    path = self.api_root + '/api/profile/billingAccounts'
    process_firecloud_request(:get, path)
  end

  # create a FireCloud billing project
  #
  # * *params*
  #   - +project_name+ (String) => name of new billing project
  #   - +billing_account+ (String) => ID of billing project (must start with billingAccounts/)
  #
  # * *return*
  #   - +Array+ of FireCloud user accounts
  def create_billing_project(project_name, billing_account)
    if billing_account.start_with?('billingAccounts/')
      path = self.api_root + '/api/billing'
      project_payload = {
          projectName: project_name,
          billingAccount: billing_account
      }.to_json
      process_firecloud_request(:post, path, project_payload)
    else
      raise RuntimeError.new("Invalid billing account: #{billing_account}; must begin with 'billingAccounts/'")
    end
  end

  # list all members of a FireCloud billing project
  #
  # * *params*
  #   - +project_id+ (String) => ID of billing project (must start with billingAccounts/)
  #
  # * *return*
  #   - +Array+ of FireCloud user accounts
  def get_billing_project_members(project_id)
    path = self.api_root + "/api/billing/#{project_id}/members"
    process_firecloud_request(:get, path)
  end

  # add a member to a FireCloud billing project
  #
  # * *params*
  #   - +project_id+ (String) => ID of billing project (must start with billingAccounts/)
  #   - +role+ (String) => role of member being added (user/owner)
  #   - +email+ (String) => email of member being added
  #
  # * *return*
  #   - +Array+ of FireCloud user accounts
  def add_user_to_billing_project(project_id, role, email)
    if BILLING_PROJECT_ROLES.include?(role)
      path = self.api_root + "/api/billing/#{project_id}/#{role}/#{email}"
      process_firecloud_request(:put, path)
    else
      raise RuntimeError.new("Invalid billing account role: #{role}; must be a member of '#{BILLING_PROJECT_ROLES.join(', ')}'")
    end
  end

  # remove a member from a FireCloud billing project
  #
  # * *params*
  #   - +project_id+ (String) => ID of billing project (must start with billingAccounts/)
  #   - +role+ (String) => role of member being added (user/owner)
  #   - +email+ (String) => email of member being added
  #
  # * *return*
  #   - +Array+ of FireCloud user accounts
  def delete_user_from_billing_project(project_id, role, email)
    if BILLING_PROJECT_ROLES.include?(role)
      path = self.api_root + "/api/billing/#{project_id}/#{role}/#{email}"
      process_firecloud_request(:delete, path)
    else
      raise RuntimeError.new("Invalid billing account role: #{role}; must be a member of '#{BILLING_PROJECT_ROLES.join(', ')}'")
    end
  end

  #######
  ##
  ## GOOGLE CLOUD STORAGE METHODS
  ##
  ## All methods are convenience wrappers around google-cloud-storage methods
  ## see https://googlecloudplatform.github.io/google-cloud-ruby/#/docs/google-cloud-storage/v1.13.0 for more detail
  ##
  #######

  # generic handler to process GCS method with retries and error handling
  #
  # * *params*
  #   - +method_name+ (String, Symbol) => name of FireCloudClient GCS method to execute
  #   - +retry_count+ (Integer) => current count of number of retries.  defaults to 0 and self-increments
  #   - +params+ (Array) => array of method parameters (passed with splat operator, so does not need to be an actual array)
  #
  # * *return*
  #   - Object depends on method, can be one of the following: +Google::Cloud::Storage::Bucket+, +Google::Cloud::Storage::File+,
  #     +Google::Cloud::Storage::FileList+, +Boolean+, +File+, or +String+

  def execute_gcloud_method(method_name, retry_count=0, *params)
    begin
      self.send(method_name, *params)
    rescue => e
      current_retry = retry_count + 1
      Rails.logger.info "error calling #{method_name} with #{params.join(', ')}; #{e.message} -- attempt ##{current_retry}"
      retry_time = retry_count * RETRY_INTERVAL
      sleep(retry_time) unless RETRY_BACKOFF_BLACKLIST.include?(method_name)
      # only retry if status code indicates a possible temporary error, and we are under the retry limit and
      # not calling a method that is blocked from retries.  In case of a NoMethodError or RuntimeError, use 500 as the
      # status code since these are unrecoverable errors
      if e.respond_to?(:code)
        status_code = e.code
      elsif e.is_a?(NoMethodError) || e.is_a?(RuntimeError)
        status_code = 500
      else
        status_code = nil
      end
      if should_retry?(status_code) && retry_count < MAX_RETRY_COUNT && !ERROR_IGNORE_LIST.include?(method_name)
        execute_gcloud_method(method_name, current_retry, *params)
      else
        # we have reached our retry limit or the response code indicates we should not retry
        unless ERROR_IGNORE_LIST.include?(method_name)
          ErrorTracker.report_exception(e, self.issuer_object, {method_name: method_name,
                                                                retry_count: current_retry, params: params})
        end
        Rails.logger.info "Retry count exceeded calling #{method_name} with #{params.join(', ')}: #{e.message}"
        raise RuntimeError.new "#{e.message}"
      end
    end
  end

  # retrieve a workspace's GCP bucket
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #
  # * *return*
  #   - +Google::Cloud::Storage::Bucket+ object
  def get_workspace_bucket(workspace_bucket_id)
    self.storage.bucket workspace_bucket_id
  end

  # retrieve all files in a GCP bucket of a workspace
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +opts+ (Hash) => hash of optional parameters, see
  #     https://googlecloudplatform.github.io/google-cloud-ruby/#/docs/google-cloud-storage/v1.13.0/google/cloud/storage/bucket?method=files-instance
  #
  # * *return*
  #   - +Google::Cloud::Storage::File::List+
  def get_workspace_files(workspace_bucket_id, opts={})
    bucket = self.get_workspace_bucket(workspace_bucket_id)
    bucket.files(opts)
  end

  # retrieve single study_file in a GCP bucket of a workspace
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filename+ (String) => name of file
  #
  # * *return*
  #   - +Google::Cloud::Storage::File+
  def get_workspace_file(workspace_bucket_id, filename)
    bucket = self.get_workspace_bucket(workspace_bucket_id)
    bucket.file filename
  end

  # check if a study_file in a GCP bucket of a workspace exists
  # this method should ideally be used outside of :execute_gcloud_method to avoid unnecessary retries
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filename+ (String) => name of file
  #
  # * *return*
  #   - +Boolean+
  def workspace_file_exists?(workspace_bucket_id, filename)
    begin
      file = self.get_workspace_file(workspace_bucket_id, filename)
      file.present?
    rescue => e
      false
    end
  end

  # add a file to a workspace bucket
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filepath+ (String) => path to file
  #   - +filename+ (String) => name of file
  #   - +opts+ (Hash) => extra options for create_file, see
  #     https://googlecloudplatform.github.io/google-cloud-ruby/#/docs/google-cloud-storage/v1.13.0/google/cloud/storage/bucket?method=create_file-instance
  #
  # * *return*
  #   - +Google::Cloud::Storage::File+
  def create_workspace_file(workspace_bucket_id, filepath, filename, opts={})
    bucket = self.get_workspace_bucket(workspace_bucket_id)
    bucket.create_file filepath, filename, opts
  end

  # copy a file to a new location in a workspace bucket
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filename+ (String) => name of target file
  #   - +destination_name+ (String) => destination of new file
  #   - +opts+ (Hash) => extra options for create_file, see
  #     https://googlecloudplatform.github.io/google-cloud-ruby/#/docs/google-cloud-storage/v1.13.0/google/cloud/storage/bucket?method=create_file-instance
  #
  # * *return*
  #   - +Google::Cloud::Storage::File+
  def copy_workspace_file(workspace_bucket_id, filename, destination_name, opts={})
    file = self.get_workspace_file(workspace_bucket_id, filename)
    file.copy destination_name, opts
  end

  # delete a file to a workspace bucket
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filename+ (String) => name of file
  #
  # * *return*
  #   - +Boolean+ indication of file deletion
	def delete_workspace_file(workspace_bucket_id, filename)
		file = self.get_workspace_file(workspace_bucket_id, filename)
		begin
			file.delete
    rescue => e
      ErrorTracker.report_exception(e, self.issuer_object, {method_name: :delete_workspace_file,
                                                            params: [workspace_bucket_id, filename]})
			Rails.logger.info("failed to delete workspace file #{filename} with error #{e.message}")
			false
		end
	end

	# retrieve single file in a GCP bucket of a workspace and download locally to portal.  will perform a chunked download
  # on files larger that 50 MB
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filename+ (String) => name of file
  #   - +destination+ (String) => destination path for downloaded file
  #   - +opts+ (Hash) => extra options for signed_url, see
  #     https://googlecloudplatform.github.io/google-cloud-ruby/#/docs/google-cloud-storage/v1.13.0/google/cloud/storage/file?method=signed_url-instance
  #
  # * *return*
  #   - +File+ object
  def download_workspace_file(workspace_bucket_id, filename, destination, opts={})
    file = self.get_workspace_file(workspace_bucket_id, filename)
    # create a valid path by combining destination directory and filename, making sure no double / exist
    end_path = [destination, filename].join('/').gsub(/\/\//, '/')
    # gotcha in case file is in a subdirectory
    if filename.include?('/')
      path_parts = filename.split('/')
      path_parts.pop
      directory = File.join(destination, path_parts)
      FileUtils.mkdir_p directory
    end
    # determine if a chunked download is needed
    if file.size > 50.megabytes
      Rails.logger.info "Performing chunked download for #{filename} from #{workspace_bucket_id}"
      # we need to determine whether or not this file has been gzipped - if so, we have to make a copy and unset the
      # gzip content-encoding as we cannot do range requests on gzipped data
      if file.content_encoding == 'gzip'
        new_file = file.copy file.name + '.tmp'
        new_file.content_encoding = nil
        remote = new_file
      else
        remote = file
      end
      size_range = 0..remote.size
      local = File.new(end_path, 'wb')
      size_range.each_slice(50.megabytes) do |range|
        range_req = range.first..range.last
        merged_opts = opts.merge(range: range_req)
        buffer = remote.download merged_opts
        buffer.rewind
        local.write buffer.read
      end
      if file.content_encoding == 'gzip'
        # clean up the temp copy
        remote.delete
      end
      Rails.logger.info "Chunked download for #{filename} from #{workspace_bucket_id} complete"
      # return newly-opened file (will need to check content type before attempting to parse)
      local
    else
      file.download end_path, opts
    end
  end

  # read the contents of a file in a workspace bucket into memory
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filename+ (String) => name of file
  #
  # * *return*
  #   - +StringIO+ contents of workspace file
  def read_workspace_file(workspace_bucket_id, filename)
    file = self.get_workspace_file(workspace_bucket_id, filename)
    file_contents = file.download
    file_contents.rewind
    file_contents
  end

  # generate a signed url to download a file that isn't public (set at study level)
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filename+ (String) => name of file
  #   - +opts+ (Hash) => extra options for signed_url, see
  #     https://googlecloudplatform.github.io/google-cloud-ruby/#/docs/google-cloud-storage/v1.13.0/google/cloud/storage/file?method=signed_url-instance
  #
  # * *return*
  #   - +String+ signed URL
  def generate_signed_url(workspace_bucket_id, filename, opts={})
    file = self.get_workspace_file(workspace_bucket_id, filename)
    file.signed_url(opts)
  end

  # generate an api url to directly load a file from GCS via client-side JavaScript
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filename+ (String) => name of file
  #
  # * *return*
  #   - +String+ signed URL
  def generate_api_url(workspace_bucket_id, filename)
    file = self.get_workspace_file(workspace_bucket_id, filename)
    if file
      file.api_url
    else
      ''
    end
  end

  # retrieve all files in a GCP directory
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +directory+ (String) => name of directory in bucket
  #   - +opts+ (Hash) => hash of optional parameters, see
  #     https://googlecloudplatform.github.io/google-cloud-ruby/#/docs/google-cloud-storage/v1.13.0/google/cloud/storage/bucket?method=files-instance
  #
  # * *return*
  #   - +Google::Cloud::Storage::File::List+
  def get_workspace_directory_files(workspace_bucket_id, directory, opts={})
    # makes sure directory ends with '/', otherwise append to prevent spurious matches
    directory += '/' unless directory.last == '/'
    opts.merge!(prefix: directory)
    self.get_workspace_files(workspace_bucket_id, opts)
  end

  #######
  ##
  ## UTILITY METHODS
  ##
  #######

  # create a map of workspace entities based on a list of names and a type
  #
  # * *params*
  #   - +entity_names+ (Array) => array of entity names
  #   - +entity_type+ (String) => type of entity that all names belong to
  #
  # * *return*
  #   - +Array+ of Hash objects: {entityName: [name], entityType: entity_type}
  def create_entity_map(entity_names, entity_type)
    map = []
    entity_names.each do |name|
      map << {entityName: name, entityType: entity_type}
    end
    map
  end

  # check if OK response code was found
  #
  # * *params*
  #   - +code+ (Integer) => integer HTTP response code
  #
  # * *return*
  #   - +Boolean+ of whether or not response is a known 'OK' response
  def ok?(code)
    [200, 201, 202, 204, 206].include?(code)
  end

  # determine if request should be retried based on response code
  #
  # * *params*
  #   - +code+ (Integer) => integer HTTP response code
  #
  # * *return*
  #   - +Boolean+ of whether or not response code indicates a retry should be executed
  def should_retry?(code)
    # if code is nil, we're not sure so retry anyway
    code.nil? || [502, 503].include?(code)
  end

  # merge hash of options into single URL query string
  #
  # * *params*
  #   - +opts+ (Hash) => hash of query parameter key/value pairs
  #
  # * *return*
  #   - +String+ of concatenated query params
  def merge_query_options(opts)
    # return nil if opts is empty, else concat
    opts.blank? ? nil : '?' + opts.to_a.map {|k,v| "#{k}=#{v}"}.join("&")
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
        if response.body.present?
          parse_response_body(response.body)
        else
          true # blank body
        end
      else
        Rails.logger.info "Unexpected response #{response.code}, not sure what to do here..."
        response.message
      end
    rescue => e
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
    is_json?(response_body) ? JSON.parse(response_body) : response_body
  end

  # determine if a response body is parseable as JSON
  #
  # * *params*
  #   - +content+ (String) => an RestClient response body
  #
  # * *return*
  #   - +Boolean+ indication if content is JSON
  def is_json?(content)
    if content.present?
      sanitized_content = content.gsub(/\n/, '') # remove newlines that may break this check
      chars = [sanitized_content[0], sanitized_content[sanitized_content.size - 1]]
      chars == %w({ }) || chars == %w([ ])
    else
      false
    end
  end

  # return a more user-friendly error message
  #
  # * *params*
  #   - +error+ (RestClient::Exception) => an RestClient error object
  #
  # * *return*
  #   - +String+ representation of complete error message, with http body if present
  def parse_error_message(error)
    if error.http_body.blank? || !is_json?(error.http_body)
      error.message
    else
      begin
        error_hash = JSON.parse(error.http_body)
        if error_hash.has_key?('message')
          # check if hash can be parsed further
          message = error_hash['message']
          if message.index('{').nil?
            return message
          else
            # attempt to extract nested JSON from message
            json_start = message.index('{')
            json = message[json_start, message.size + 1]
            new_message = JSON.parse(json)
            if new_message.has_key?('message')
              new_message['message']
            else
              new_message
            end
          end
        else
          return error.message
        end
      rescue => e
        # reporting error doesn't help, so ignore
        Rails.logger.error e.message
        error.message + ': ' + error.http_body
      end
    end
  end

  # URI-encode workspace identifiers (namespaces, workspaces) for use in API requests
  #
  # * *params*
  #   - +identifier+ (String) => Name of Terra namespace/workspace
  #
  # * *returns*
  #   - +String+ => URI-encoded namespace/workspace
  def uri_encode(identifier)
    URI.escape(identifier)
  end
end
