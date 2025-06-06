##
# FireCloudClient: Class that wraps API calls to both FireCloud and Google Cloud Storage to manage the CRUDing of both
# FireCloud workspaces and files inside the associated GCP storage buckets, as well as billing/user group/workflow submission
# management.
#
# Uses the gems googleauth (for generating access tokens), google-cloud-storage (for bucket/file access),
# and rest-client (for HTTP calls)
#
# Author::  Jon Bistline  (mailto:bistline@broadinstitute.org)

class FireCloudClient
  extend ServiceAccountManager
  include GoogleServiceClient
  include ApiHelpers

  attr_accessor :user, :project, :access_token, :api_root, :storage, :expires_at, :service_account_credentials

  #
  # CONSTANTS
  #

  # base url for all API calls
  BASE_URL = 'https://api.firecloud.org'.freeze
  BASE_SAM_SERVICE_URL = 'https://sam.dsde-prod.broadinstitute.org'.freeze
  BASE_RAWLS_SERVICE_URL = 'https://rawls.dsde-prod.broadinstitute.org'.freeze
  # default auth scopes for client tokens
  GOOGLE_SCOPES = %w[
    https://www.googleapis.com/auth/userinfo.profile
    https://www.googleapis.com/auth/userinfo.email
    https://www.googleapis.com/auth/devstorage.read_only
  ].freeze
  # List of URLs/Method names to never retry on or report error, regardless of error state
  ERROR_IGNORE_LIST = [
    "#{BASE_URL}/register", "#{BASE_URL}/api/groups", "#{BASE_SAM_SERVICE_URL}/api/termsOfService/v1/user/self"
  ].freeze
  # List of URLs/Method names to ignore incremental backoffs on (in cases of UI blocking)
  RETRY_BACKOFF_DENYLIST = ["#{BASE_URL}/register", :generate_signed_url, :generate_api_url].freeze
  # default namespace used for all FireCloud workspaces owned by the 'portal'
  PORTAL_NAMESPACE = ENV['PORTAL_NAMESPACE'].present? ? ENV['PORTAL_NAMESPACE'] : 'single-cell-portal'
  # Permission values allowed for FireCloud workspace ACLs
  WORKSPACE_PERMISSIONS = ['OWNER', 'READER', 'WRITER', 'NO ACCESS'].freeze
  # List of FireCloud user group roles
  USER_GROUP_ROLES = %w[admin member].freeze
  # List of FireCloud billing project roles
  BILLING_PROJECT_ROLES = %w[user owner].freeze
  # List of projects where computes are not permitted (sets canCompute to false for all users by default, can only be overridden
  # by PROJECT_OWNER)
  COMPUTE_DENYLIST = %w[single-cell-portal].freeze
  # Name of user group to set as workspace owner for user-controlled billing projects.  Reduces the amount of
  # groups the portal service account needs to be a member of
  # defaults to the Terra billing project this instance is configured against, plus "-sa-owner-group"
  WS_OWNER_GROUP_NAME = "#{PORTAL_NAMESPACE}-sa-owner-group".freeze

  ##
  # SERVICE NAMES AND DESCRIPTIONS
  #
  # The following constants are named FireCloud "services" that cover various pieces of functionality that
  # SCP depends on.  These names are stored here to reduce duplication and prevent typos.
  # A list of all available service names can be retrieved with FireCloudClient#api_status
  ##

  # Rawls is the largest service that pertains to workspaces and pipeline submissions via the managed Cromwell instance
  # SCP uses Rawls for updating studies, uploading/parsing files, launching workflows
  RAWLS_SERVICE = 'Rawls'.freeze
  # SAM holds most of the workspace permissions and other features
  # SCP uses Sam for updating studies, uploading/parsing files
  SAM_SERVICE = 'Sam'.freeze
  # Agora covers the Methods repository and other analysis-oriented features
  # SCP uses Agora for configuring new analyses, submitting workflows
  AGORA_SERVICE = 'Agora'.freeze
  # Thurloe covers Terra profiles and billing projects
  # SCP uses Thurloe for managing user's Terra profiles and billing projects
  THURLOE_SERVICE = 'Thurloe'.freeze
  # Workspaces come with GCP buckets, and the GoogleBuckets service helps manage permissions
  # SCP requires GoogleBuckets to be up for uploading/downloading files, even though SCP uses the GCS JSON API directly
  # via the google-cloud-storage gem.
  BUCKETS_SERVICE = 'GoogleBuckets'.freeze

  ##
  # METHODS
  ##

  # initialize is called after instantiating with FireCloudClient.new
  # will set the access token, FireCloud api url root and GCP storage driver instance
  #
  # * *params*
  #   - +service_account+ (String) => File path to JSON keyfile for service account
  #   - +user+: (User) => User object from which access tokens are generated
  #   - +project+: (String) => Default GCP Project to use (can be overridden by other parameters)
  #   - +api_root+ (String) => URL for base Terra orchestration API instance (defaults to api.firecloud.org)
  #
  # * *return*
  #   - +FireCloudClient+ object
  def initialize(user: nil, project: PORTAL_NAMESPACE, service_account: self.class.get_primary_keyfile, api_root: BASE_URL)
    # when initializing without a user, default to base configuration
    if user.nil?
      # instantiate Google Cloud Storage driver to work with files in workspace buckets
      # if no keyfile is present, use environment variables
      storage_attr = {
        project_id: PORTAL_NAMESPACE,
        timeout: 3600
      }

      if !service_account.blank?
        storage_attr.merge!(credentials: service_account)
        self.service_account_credentials = service_account
      end

      self.access_token = self.class.generate_access_token(service_account)
      self.project = project

      self.storage = Google::Cloud::Storage.new(**storage_attr)

      # set expiration date of token
      self.expires_at = Time.zone.now + self.access_token['expires_in']
    else
      self.user = user
      self.project = project
      # user.token_for_api_call will retrieve valid access token to use, if present
      self.access_token = user.token_for_api_call
      # set a default timeout if no token was retrieved; this prevents errors when attempting requests, although
      # the request will most likely fail with a 401, which is expected
      self.expires_at = self.access_token['expires_at'].present? ? self.access_token['expires_at'] : Time.now.in_time_zone + 1.hour

      # use user-defined project instead of portal default
      # if no keyfile is present, use environment variables
      storage_attr = {
          project_id: project,
          timeout: 3600
      }

      if !service_account.blank?
        storage_attr.merge!(credentials: service_account)
        self.service_account_credentials = service_account
      end

      self.storage = Google::Cloud::Storage.new(**storage_attr)
    end
    self.api_root = api_root.chomp('/')
  end

  # return a hash of instance attributes for this client
  #
  # * *return*
  #   - +Hash+ of values for all instance variables for this client
  def attributes
    {
      user:,
      project:,
      access_token: 'REDACTED',
      issuer:,
      api_root:,
      storage:, expires_at:,
      service_account_credentials:
    }
  end

  #
  # TOKEN METHODS
  #

  ##
  ## STORAGE INSTANCE METHODS
  ##

  # renew the storage driver
  #
  # * *params*
  #   - +project_name+ (String )=> name of GCP project, default project is value of PORTAL_NAMESPACE
  #
  # * *return*
  #   - +Google::Cloud::Storage+ instance
  def refresh_storage_driver(project_name=PORTAL_NAMESPACE)
    storage_attr = {
        project_id: project_name,
        timeout: 3600
    }
    if !ENV['SERVICE_ACCOUNT_KEY'].blank?
      storage_attr.merge!(credentials: self.class.get_primary_keyfile)
    end
    new_storage = Google::Cloud::Storage.new(**storage_attr)
    self.storage = new_storage
    new_storage
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

    # set default headers, appending application identifier including hostname for disambiguation
    # allow for override of default application/json content_type and accept headers
    headers = get_default_headers(content_type: opts[:content_type])

    # if uploading a file, remove Content-Type/Accept headers to use default x-www-form-urlencoded type on POSTs
    if request_opts[:file_upload]
      headers.reject! {|header, value| %w(Content-Type Accept).include? header }
    end

    # process request
    begin
      response = RestClient::Request.execute(method: http_method, url: path, payload: payload, headers: headers)
      # handle response using helper
      handle_response(response)
    rescue RestClient::Exception => e
      current_retry = retry_count + 1
      context = " encountered when requesting '#{path}', attempt ##{current_retry}"
      log_message = "#{e.message}: #{e.http_body}; #{context}"
      Rails.logger.error log_message

      # only retry if status code indicates a possible temporary error, and we are under the retry limit and
      # not calling a method that is blocked from retries
      if should_retry?(e.http_code) && retry_count < ApiHelpers::MAX_RETRY_COUNT && !ERROR_IGNORE_LIST.include?(path)
        retry_time = retry_interval_for(current_retry)
        sleep(retry_time) unless RETRY_BACKOFF_DENYLIST.include?(path) # only sleep if non-blocking
        process_firecloud_request(http_method, path, payload, opts, current_retry)
      else
        # we have reached our retry limit or the response code indicates we should not retry
        unless ERROR_IGNORE_LIST.include?(path)
          ErrorTracker.report_exception(e, self.issuer_object, { method: http_method, url: path, payload: payload,
                                                                 opts: opts, retry_count: retry_count})
        end
        error_message = parse_error_message(e)
        Rails.logger.error "Retry count exceeded when requesting '#{path}' - #{error_message}"
        raise e
      end
    rescue => e
      # fallback error handler
      Rails.logger.error "Unknown error: #{e.class} - #{e.message}"
      raise e
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
    begin
      response = RestClient::Request.execute(method: :get, url: path, headers: get_default_headers)
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
  #   - +no_workspace_owner+ (Boolean) => T/F to skip assigning workspace owner to user making request (default: false)
  #   - +authorization_domains+ (Array<String>) => list of authorization domains to add to workspace
  #
  # * *return*
  #   - +Hash+ object of workspace instance
  def create_workspace(workspace_namespace, workspace_name, no_workspace_owner=false, *authorization_domains)
    path = self.api_root + '/api/workspaces'
    # construct payload for POST
    payload = {
        namespace: workspace_namespace,
        name: workspace_name,
        attributes: {},
        noWorkspaceOwner: no_workspace_owner,
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

  # passthru to determine if a workspace exists
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of workspace
  #
  # * *return*
  #   - +Boolean+
  def workspace_exists?(workspace_namespace, workspace_name)
    begin
      get_workspace(workspace_namespace, workspace_name)
      true
    rescue RestClient::NotFound
      false
    end
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
    # delete workspace endpoint throws 406 with JSON content_type, set to text/plain
    process_firecloud_request(:delete, path, nil, { content_type: 'text/plain' })
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
      raise RuntimeError.new("Invalid FireCloud ACL permission setting \"#{permission}\"; must be member of #{WORKSPACE_PERMISSIONS.join(', ')}")
    end
  end

  # check the read access for a workspace bucket, and issues FastPass process if permissions are not as they should yet
  # OK responses have to content, but 40x or 500 will contain JSON stack trace
  # In the case of 403, a FastPass request is submitted for the corresponding user
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of workspace
  #
  # * *returns*
  #   - +True+, +Hash+ true for OK, error stack trace for other scenarios
  #
  # * *raises*
  #   - (RestClient::Exception) if workspace is not found, or other internal error
  def check_bucket_read_access(workspace_namespace, workspace_name)
    ws_identifier = "#{workspace_namespace}/#{workspace_name}"
    path = BASE_RAWLS_SERVICE_URL + "/api/workspaces/#{ws_identifier}/checkBucketReadAccess"
    begin
      Rails.logger.info "Checking bucket access on #{ws_identifier} with tracking identifier: #{tracking_identifier}"
      # make raw request for specific error handling in 403 case
      RestClient::Request.execute(method: :get, url: path, headers: get_default_headers)
      true
    rescue RestClient::Forbidden
      # only rescue 403 as this means FastPass is being issued
      Rails.logger.info "Permissions not yet synchronized for #{ws_identifier}, FastPass request initiated"
      false
    rescue RestClient::Exception => e
      ErrorTracker.report_exception(e, issuer_object, { method: :get, url: path })
      error_message = parse_error_message(e)
      Rails.logger.error "Error checking bucket read access in #{ws_identifier} - #{error_message}"
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

  ##
  ## WORKSPACE ENTITY METHODS
  ##

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
      raise RuntimeError.new("Invalid FireCloud user group role \"#{user_role}\"; must be one of \"#{USER_GROUP_ROLES.join(', ')}\"")
    end
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
    path = self.api_root + '/api/billing/v2'
    process_firecloud_request(:get, path)
  end

  # list all members of a FireCloud billing project
  #
  # * *params*
  #   - +project_id+ (String) => ID of billing project (must start with billingAccounts/)
  #
  # * *return*
  #   - +Array+ of FireCloud user accounts
  def get_billing_project_members(project_id)
    path = self.api_root + "/api/billing/v2/#{project_id}/members"
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
      path = self.api_root + "/api/billing/v2/#{project_id}/members/#{role}/#{email}"
      process_firecloud_request(:put, path)
    else
      raise RuntimeError.new("Invalid billing account role \"#{role}\"; must be a member of \"#{BILLING_PROJECT_ROLES.join(', ')}\"")
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
      path = self.api_root + "/api/billing/v2/#{project_id}/members/#{role}/#{email}"
      process_firecloud_request(:delete, path)
    else
      raise RuntimeError.new("Invalid billing account role \"#{role}\"; must be a member of \"#{BILLING_PROJECT_ROLES.join(', ')}\"")
    end
  end

  ##
  # PET SERVICE ACCOUNT METHODS
  # these methods reference the SAM API directly for issuing pet service account tokens/json keyfiles
  # NOTE: the FireCloudClient instance calling these methods must be initialized using a User object
  # for authentication purposes, otherwise downstream calls will return 403
  ##

  # create a new instance of FireCloudClient, but use a pet service account keyfile
  # will only work with users that have been registered in Terra
  #
  # * *params*
  #   - +user+: (User) => User object from which access tokens are generated
  #   - +project+: (String) => Default GCP Project to use (can be overridden by other parameters)
  #
  # * *return*
  #   - +FireCloudClient+ instance, or nil if user has not registered with Terra
  def self.new_with_pet_account(user, project)
    # create a temporary client in order to retrieve the user's pet service account keyfile
    tmp_client = new(user:, project:)
    if tmp_client.registered?
      pet_service_account_json = tmp_client.get_pet_service_account_key(project)
      new(user:, project:, service_account: pet_service_account_json)
    else
      nil
    end
  end

  # issue an access_token for a user's pet service account in the requested project
  #
  # * *params*
  #   - +project_name+ (String) => Name of a FireCloud billing project in which pet service account resides
  #
  # * *returns*
  #   - (Hash) => OAuth2 access token hash, with the following attributes
  #     - +access_token+ (String) => OAuth2 access token
  #     - +expires_in+ (Integer) => duration of token, in seconds
  #     - +expires_at+ (String) => timestamp of when token expires
  def get_pet_service_account_token(project_name)
    path = BASE_SAM_SERVICE_URL + "/api/google/v1/user/petServiceAccount/#{project_name}/token"
    # normal scopes, plus read-only access for storage objects,
    # which omits unnecessary billing scope from GOOGLE_SCOPES
    token = process_firecloud_request(:post, path, GOOGLE_SCOPES.to_json)
    token.gsub(/\"/, '') # gotcha for removing escaped quotes in response body

    expires_in = 3600 # 1 hour, in seconds
    expires_at = Time.zone.now + expires_in

    return {
      'access_token' => token,
      'expires_in' => expires_in,
      'expires_at' => expires_at
    }
  end

  # get JSON keyfile contents for a user's pet service account in the requested project
  # response from this API call can be passed to FireCloudClient.new(**params)
  # to create an instance of FireCloudClient that is able to call GCS methods as the user in the request project
  #
  # * *params*
  #   - +project_name+ (String) => Name of a FireCloud billing project in which pet service account resides
  #
  # * *returns*
  #   - (Hash) parsed contents of pet service account JSON keyfile
  def get_pet_service_account_key(project_name)
    path = BASE_SAM_SERVICE_URL + "/api/google/v1/user/petServiceAccount/#{project_name}/key"
    process_firecloud_request(:get, path)
  end

  # get a user's Terra terms of service status (only available directly from Sam)
  # contains information on acceptance version, date, and whether user is permitted system access based on state
  #
  # * *returns*
  #   - (Hash) {
  #       acceptedOn: DateTime, isCurrentVersion: Boolean, latestAcceptedVersion: Integer, permitsSystemUsage: Boolean
  #     }
  def get_terms_of_service
    path = "#{BASE_SAM_SERVICE_URL}/api/termsOfService/v1/user/self"
    process_firecloud_request(:get, path)
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
  def execute_gcloud_method(method_name, retry_count = 0, *params)
    begin
      self.send(method_name, *params)
    rescue => e
      status_code = extract_status_code(e)
      current_retry = retry_count + 1
      if should_retry?(status_code) && retry_count < ApiHelpers::MAX_RETRY_COUNT && !ERROR_IGNORE_LIST.include?(method_name)
        Rails.logger.info "error calling #{method_name} with #{params.join(', ')}; #{e.message} -- attempt ##{current_retry}"
        retry_time = retry_interval_for(current_retry)
        sleep(retry_time) unless RETRY_BACKOFF_DENYLIST.include?(method_name)
        execute_gcloud_method(method_name, current_retry, *params)
      else
        # we have reached our retry limit or the response code indicates we should not retry
        unless ERROR_IGNORE_LIST.include?(method_name)
          ErrorTracker.report_exception(e, self.issuer_object, { method_name: method_name,
                                                                 retry_count: current_retry, params: params})
        end
        Rails.logger.info "Retry count exceeded calling #{method_name} with #{params.join(', ')}: #{e.message}"
        raise e.message # raise implicitly creates RuntimeError
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
    bucket.files(**opts)
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
    bucket.create_file(filepath, filename, **opts)
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
    file.copy(destination_name, **opts)
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
      ErrorTracker.report_exception(e, self.issuer_object, { method_name: :delete_workspace_file,
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
      file.download end_path, **opts
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
    file.signed_url(**opts)
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
    self.get_workspace_files(workspace_bucket_id, **opts)
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

  # extract a status code from an error GCS call, accounting for upstream api.firecloud.org calls
  #
  # * *params*
  #   - +error+ (Multiple) => Error from either Google Cloud Storage or Firecloud API
  #
  # * *returns*
  #   - (Integer) => HTTP status code, substituting 500 for unknown errors
  def extract_status_code(error)
    return 500 if error.is_a?(RuntimeError)

    error.try(:http_code) || error.try(:code) || 500
  end
end
