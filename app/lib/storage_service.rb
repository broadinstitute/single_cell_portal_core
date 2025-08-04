# main handler for storage service operations using vendor-specific clients
class StorageService
  extend ServiceAccountManager
  extend Loggable

  # API clients that can use StorageService
  # Minitest::Mock is included here to facilitate testing
  ALLOWED_CLIENTS = [StorageProvider::Gcs, Minitest::Mock].freeze

  # exceptions that will be handled and reported
  HANDLED_EXCEPTIONS = [RuntimeError, RestClient::Exception, Google::Cloud::Error, Google::Apis::ClientError].freeze

  # load the configured storage client for the application, specific to a given study
  # the client class can be set in application.rb or via STORAGE_CLIENT environment variable
  def self.load_client(study: nil)
    configured_client = Rails.configuration.storage_client
    unless const_defined?(configured_client) && ALLOWED_CLIENTS.map(&:to_s).include?(configured_client)
      raise ArgumentError, "#{configured_client} not one of allowed clients: #{ALLOWED_CLIENTS.join(', ')}"
    end

    # if study is provided, use its cloud project; otherwise use the configured project or environment variable
    project = study&.cloud_project || ENV['GOOGLE_CLOUD_PROJECT']
    const_get(configured_client).new(project)
  end

  # generic handler to call an underlying client method and forward all positional/keyword params
  #
  # * *params*
  #   - +client+ (Object) => any API client from ALLOWED_CLIENTS
  #   - +client_method+ (String, Symbol) => underlying client method to invoke
  #   - +args+ (Multiple) => any positional parameters for client_method
  #   - +kwargs+ (Hash) => any keyword parameters for client_method
  #
  # * *returns*
  #   - (Multiple) => return from client_method
  #
  # * *raises*
  #   - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  #   - any exception from the client method, which will be logged and reported
  def self.call_client(client, client_method, *args, **kwargs)
    unless ALLOWED_CLIENTS.map(&:to_s).include?(client.class.name)
      raise ArgumentError, "#{client.class} not one of allowed clients: #{ALLOWED_CLIENTS.join(', ')}"
    end

    client.send(client_method, *args, **kwargs)
  rescue *HANDLED_EXCEPTIONS => e
    log_message("Error calling #{client_method} on #{client.class}: #{e.class} - #{e.message}", level: :error)
    ErrorTracker.report_exception(e, client.issuer, client, client_method:, args:, kwargs:)
    raise e
  end

  # create a storage bucket for a given study and assign all acls and autoclasses
  #
  # * *params*
  #   - +client+ (StorageProvider) => storage client to use for creating the bucket
  #   - +study+ (Study) => study for which to create the bucket
  #
  # * *yields*
  #   - +Google::Cloud::Storage::Bucket+
  #
  # * *raises*
  #   - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  #   - any exception from the client method, which will be logged and reported
  def self.create_study_bucket(client, study)
    bucket_id = study.bucket_id
    call_client(client, :create_study_bucket, bucket_id)
    call_client(client, :enable_bucket_autoclass, bucket_id) if client.respond_to?(:enable_bucket_autoclass)
    call_client(client, :update_bucket_acl, bucket_id, study.user.email, :writer)
    study.study_shares.each do |share|
      role = share.permission == 'Edit' ? :writer : :reader
      call_client(client, :update_bucket_acl, bucket_id, share.email, role)
    end
  end

  # remove a storage bucket for a given study and delete all files in it
  # all files in the bucket must be deleted before the bucket itself can be removed
  #
  # * *params*
  #   - +client+ (StorageProvider) => storage client to use for removing the bucket
  #   - +study+ (Study) => study for which to remove the bucket
  #
  # * *raises*
  #   - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  #   - any exception from the client method, which will be logged and reported
  def self.remove_study_bucket(client, study)
    files = call_client(client, :bucket_files, study.bucket_id)
    Parallel.map(files, in_threads: 10, &:delete)
    call_client(client, :delete_bucket, study.bucket_id)
  end
end
