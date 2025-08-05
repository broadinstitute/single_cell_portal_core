# main handler for storage service operations using vendor-specific clients
class StorageService
  extend ServiceAccountManager
  extend Loggable

  # API clients that can use StorageService
  ALLOWED_CLIENTS = [StorageProvider::Gcs].freeze

  # exceptions that will be handled and reported
  HANDLED_EXCEPTIONS = [RuntimeError, Google::Cloud::Error, Google::Apis::Error].freeze

  # load the configured storage client for the application, specific to a given study
  # the client class can be set in application.rb or via STORAGE_CLIENT environment variable
  def self.load_client(study: nil)
    configured_client = Rails.configuration.storage_client
    validate_client(configured_client)

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
    validate_client(client.class.name)

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
    log_message "Creating study bucket #{bucket_id} for study #{study.accession}"
    client.create_study_bucket(bucket_id)
    log_message "Enabling autoclass on study bucket #{bucket_id} for study #{study.accession}"
    client.enable_bucket_autoclass(bucket_id) if client.respond_to?(:enable_bucket_autoclass)
    log_message "Setting ACLs on study bucket #{bucket_id} for study #{study.accession}"
    set_study_bucket_acl(client, study)
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
    log_message "Removing all files from study bucket #{study.bucket_id} for study #{study.accession}"
    files = client.load_study_bucket_files(study.bucket_id)
    Parallel.map(files, in_threads: 10, &:delete)
    log_message "Deleting study bucket #{study.bucket_id} for study #{study.accession}"
    client.delete_study_bucket(study.bucket_id)
  end

  # determine if a bucket study bucket exists
  #
  # * *params*
  #   - +client+ (StorageProvider) => storage client to use for checking the bucket existence
  #   - +study+ (Study) => study for which to check the bucket existence
  #
  # * *returns*
  #   - +Boolean+ => true if the bucket exists, false otherwise
  #
  # * *raises*
  #   - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  #   - any exception from the client method, which will be logged and reported
  def self.study_bucket_exists?(client, study)
    client.bucket_exists?(study.bucket_id)
  rescue *HANDLED_EXCEPTIONS
    false
  end

  # update the ACLs for a study bucket based on the study's shares
  #
  # * *params*
  #   - +client+ (StorageProvider) => storage client to use for updating the ACLs
  #   - +study+ (Study) => study for which to update the bucket ACLs
  #
  # * *raises*
  #   - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  #   - any exception from the client method, which will be logged and reported
  def self.set_study_bucket_acl(client, study)
    existing_acl = client.get_study_bucket_acl(study.bucket_id)
    log_message "Assigning writer acl for study owner in #{study.accession}"
    client.update_study_bucket_acl(study.bucket_id, study.user.email, role: :writer)
    study.study_shares.each do |share|
      user_acl = "user-#{share.email}"
      role = share.permission == 'Edit' ? 'writer' : 'reader'
      acl_method = role.pluralize
      next if existing_acl.send(acl_method).include?(user_acl)

      log_message "Assigning #{role} acl for share #{share.id} in #{study.accession}"
      client.update_study_bucket_acl(study.bucket_id, share.email, role:)
    end
  end

  # remove a user's share from a study bucket
  #
  # * *params*
  #   - +client+ (StorageProvider) => storage client to use for updating the ACLs
  #   - +study+ (Study) => study for which to update the bucket ACLs
  #   - +share+ (StudyShare) => share to remove
  #
  # * *raises*
  #   - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  #   - any exception from the client method, which will be logged and reported
  def self.remove_user_share(client, study, share)
    log_message "Removing acl for share #{share.id} in #{study.accession}"
    client.update_study_bucket_acl(study.bucket_id, share.email, role: nil, delete: true)
  end

  # generate a signed URL for downloading a study file
  #
  # * *params*
  #  - +client+ (StorageProvider) => storage client to use for generating the signed URL
  #  - +study+ (Study) => study for which the file is stored
  #  - +study_file+ (StudyFile) => file to download
  #
  # * *returns*
  # - +String+ => signed URL for downloading the file via browser
  #
  # * *raises*
  # - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  # - any exception from the client method, which will be logged and reported
  def self.download_study_file(client, study, study_file)
    file_location = study_file.bucket_location
    call_client(client, :download_bucket_file, study.bucket_id, file_location, expires: 15)
  end

  # generate a media URL for streaming a study file
  #
  # * *params*
  #  - +client+ (StorageProvider) => storage client to use for generating the signed URL
  #  - +study+ (Study) => study for which the file is stored
  #  - +study_file+ (StudyFile) => file to download
  #
  # * *returns*
  # - +String+ => signed URL for downloading the file via browser
  #
  # * *raises*
  # - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  # - any exception from the client method, which will be logged and reported
  def self.stream_study_file(client, study, study_file)
    file_location = study_file.bucket_location
    call_client(client, :stream_bucket_file, study.bucket_id, file_location)
  end

  # validate that the client is one of the allowed client classes
  # will allow mocking in tests via Rails.env.test? check
  #
  # * *params*
  #   - +client_class+ (String, Symbol) => name of the client to validate
  #
  # * *raises*
  #   - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  def self.validate_client(client_class)
    unless const_defined?(client_class) && (ALLOWED_CLIENTS.map(&:to_s).include?(client_class) || Rails.env.test?)
      raise ArgumentError, "#{client_class} not one of allowed clients: #{ALLOWED_CLIENTS.join(', ')}"
    end
  end
end
