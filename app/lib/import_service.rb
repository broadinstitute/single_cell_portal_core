# service for loading data into SCP from external APIs, such as the NeMO Identifiers API or HCA Azul service
class ImportService
  extend ServiceAccountManager

  # API clients that can use ImportService
  ALLOWED_CLIENTS = [NemoClient, HcaAzulClient].freeze

  # allowed configuration classes
  ALLOWED_CONFIGS = [ImportServiceConfig::Nemo]

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

  def self.import_from(config_class, ...)
    raise "unsupported config: #{config_class}" unless defined?(config_class) && ALLOWED_CONFIGS.include?(config_class)

    configuration = config_class.new(...)
    begin
      study, study_file = configuration.create_models_and_copy_files
    rescue => e
      puts "Error importing from #{config_class}; #{e.class} -- #{e.message}"
      ErrorTracker.report_exception(e, config.user)
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
  #   - +bucket+ (Google::Cloud::Storage::Bucket) => public bucket instance from :load_bucket
  #   - +filepath+ (String) => path to file in public bucket
  #
  # * *returns*
  #   - (Google::Cloud::Storage::File)
  def self.load_public_gcp_file(bucket, filepath)
    bucket.file filepath, skip_lookup: true
  end

  # move a file from a remote source to a workspace bucket for parsing
  #
  # * *params*
  #   - +remote_url+ (String) => URL for accessing remote file
  #   - +bucket_id+ (String) => workspace GCP bucket ID
  #
  # * *returns*
  #   - (Google::Cloud::Storage::File)
  #
  # * *raises*
  #   - (ArgumentError) => invalid remote protocol for file (must be http, https, or gs)
  #   - (Google::Apis::ClientError, RestClient::NotFound) cannot find remote file
  def self.copy_file_to_bucket(remote_url, bucket_id)
    protocol = remote_url.split('://').first
    case protocol
    when 'https', 'http'
      tmp_file = RestClient::Request.execute(method: :get, url: remote_url, raw_response: true)
      bucket = storage.bucket bucket_id
      filename = remote_url.split('/').last
      bucket.create_file tmp_file.file, filename
    when 'gs'
      bucket, filepath, filename = parse_gs_url(remote_url)
      public_bucket = load_public_bucket(bucket)
      public_file = load_public_gcp_file(public_bucket, filepath)
      public_file.copy bucket_id, filename
    else
      raise ArgumentError, "cannot retrieve file from #{remote_url}: unknown protocol #{protocol}"
    end
  end

  # get a bucket, path and filename from a gs:// url
  #
  # * *params*
  #   - +gs_url+ (String) => url in gs:// format
  #
  # * *returns*
  #   - (Array) => bucket, filepath, and filename as array
  def self.parse_gs_url(gs_url)
    parts = gs_url.delete_prefix('gs://').split('/')
    bucket = parts.shift
    filepath = parts.join('/')
    filename = parts.last
    [bucket, filepath, filename]
  end
end
