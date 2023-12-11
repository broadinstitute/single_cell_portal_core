# service for loading data into SCP from external APIs, such as the NeMO Identifiers API or HCA Azul service
class ImportService
  extend ServiceAccountManager
  extend Loggable

  # API clients that can use ImportService
  ALLOWED_CLIENTS = [NemoClient, HcaAzulClient].freeze

  # allowed configuration classes
  ALLOWED_CONFIGS = [ImportServiceConfig::Nemo, ImportServiceConfig::Hca].freeze

  # generic handler to call an underlying client method and forward all positional/keyword params
  #
  # * *params*
  #   - +client+ (Object) => any API client from ALLOWED_CLIENTS
  #   - +client_method+ (String, Symbol) => underlying client method to invoke
  #   - +...+ (Multiple) => any positional or keyword parameters for client_method
  #
  # * *returns*
  #   - (Multiple) => return from client_method
  def self.call_api_client(client, client_method, ...)
    unless ALLOWED_CLIENTS.map(&:to_s).include?(client.class.name)
      raise ArgumentError, "#{client.class} not one of allowed clients: #{ALLOWED_CLIENTS.join(', ')}"
    end

    client.send(client_method, ...)
  end

  # wrapper around ImportServiceConfig#create_models_and_copy_files that includes error handling & reporting
  #
  # * *params*
  #   - +config_class+ (ImportServiceConfig) => class of ImportServiceConfig to use, from ALLOWED_CONFIGS
  #   - +...+ (Various) => parameters to pass to underlying config_class
  #
  # * *returns*
  #   - (Array<Study, StudyFile>) => newly imported Study and StudyFile
  def self.import_from(config_class, ...)
    raise "unsupported config: #{config_class}" unless defined?(config_class) && ALLOWED_CONFIGS.include?(config_class)

    configuration = config_class.new(...)
    unless configuration.valid?
      raise configuration.errors.full_messages.join(', ')
    end

    begin
      study, study_file = configuration.import_from_service
      # TODO: uncomment this block after file parsing is enabled for NeMO and SCP-5400 is complete
      # extra work will be required but is unknown until we have the dataset (e.g. populating AnnData data_fragments)
      identifier = "#{study.accession} (#{study.external_identifier})"
      log_message "Ingesting file: #{study_file.upload_file_name} (#{study_file.external_identifier}) from imported study #{identifier}"
      FileParseService.run_parse_job(study_file, study, study.user)
      [study, study_file]
    rescue RuntimeError, RestClient::Exception, Google::Apis::ClientError => e
      log_message("Error importing from #{config_class}: #{e.class} - #{e.message}", level: :error)
      ErrorTracker.report_exception(e, configuration.user)
      study = Study.find_by(external_identifier: configuration.study_id)
      study_file = StudyFile.find_by(external_identifier: configuration.file_id)
      [study, study_file].compact.each do |instance|
        DeleteQueueJob.new(instance).delay.perform
      end
      nil
    end
  end

  # GCP storage client for accessing files in public GCP buckets
  #
  # * *returns*
  #   - (Google::Cloud::Storage)
  def self.storage
    @@storage ||= Google::Cloud::Storage.new(
      project_id: compute_project, timeout: 3600, credentials: get_primary_keyfile
    )
  end

  # load a public GCP bucket for copying public files to workspace buckets
  # since buckets may be requester pay, setting user_project: true allows egress to be billed back to SCP
  #
  # * *params*
  #   - +bucket_id+ (String) => name of public bucket
  #
  # * *returns*
  #   - (Google::Cloud::Storage::Bucket)
  def self.load_public_bucket(bucket_id)
    storage.bucket bucket_id, skip_lookup: true, user_project: true
  end

  # load a public GCP file for copying
  #
  # * *params*
  #   - +bucket_id+ (String) => name of public bucket
  #   - +filepath+ (String) => path to file in public bucket
  #
  # * *returns*
  #   - (Google::Cloud::Storage::File)
  def self.load_public_gcp_file(bucket_id, filepath)
    bucket = load_public_bucket(bucket_id)
    bucket.file filepath, skip_lookup: true
  end

  # move a file from a remote source to a workspace bucket for parsing
  #
  # * *params*
  #   - +remote_url+ (String) => URL for accessing remote file
  #   - +bucket_id+ (String) => workspace GCP bucket ID
  #   - +filename+ (String) => name of file to create in workspace bucket
  #
  # * *returns*
  #   - (Google::Cloud::Storage::File)
  #
  # * *raises*
  #   - (ArgumentError) => invalid remote protocol for file (must be http, https, or gs)
  #   - (Google::Apis::ClientError, RestClient::NotFound) cannot find remote file
  def self.copy_file_to_bucket(remote_url, bucket_id, filename)
    protocol = remote_url.split('://').first
    case protocol
    when 'https', 'http'
      tmp_file = RestClient::Request.execute(method: :get, url: remote_url, raw_response: true)
      bucket = storage.bucket bucket_id
      bucket.create_file tmp_file.file, filename
    when 'gs'
      bucket, filepath = parse_gs_url(remote_url)
      public_file = load_public_gcp_file(bucket, filepath)
      public_file.copy bucket_id, filename
    else
      raise ArgumentError, "cannot retrieve file from #{remote_url}: unknown protocol #{protocol}"
    end
  end

  # get a bucket and path from a gs:// url
  #
  # * *params*
  #   - +gs_url+ (String) => url in gs:// format
  #
  # * *returns*
  #   - (Array<String, String>) => bucket, filepath as array
  def self.parse_gs_url(gs_url)
    parts = gs_url.delete_prefix('gs://').split('/')
    bucket = parts.shift
    filepath = parts.join('/')
    [bucket, filepath]
  end

  # wrapper to remove workspaces if imports fail
  #
  # * *params*
  #   - +study+ (Study) => study from which to remove Terra workspace
  def self.remove_study_workspace(study)
    if ApplicationController.firecloud_client.workspace_exists?(study.firecloud_project, study.firecloud_workspace)
      ApplicationController.firecloud_client.delete_workspace(study.firecloud_project, study.firecloud_workspace)
    end
  end
end
