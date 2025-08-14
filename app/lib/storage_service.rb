# main handler for storage service operations using vendor-specific clients
class StorageService
  extend ServiceAccountManager

  # API clients that can use StorageService
  ALLOWED_CLIENTS = [StorageProvider::Gcs].freeze

  # exceptions that will be handled and reported
  HANDLED_EXCEPTIONS = [RuntimeError, Google::Cloud::Error, Google::Apis::Error].freeze

  # load the configured storage client for the application, specific to a given study or cloud project
  # the client class can be set in application.rb or via STORAGE_CLIENT environment variable
  def self.load_client(study: nil, cloud_project: nil, public_access: false)
    configured_client = Rails.configuration.storage_client
    validate_client(configured_client)

    # if study is provided, use its cloud project; otherwise use the configured project or environment variable
    project = cloud_project || study&.cloud_project || ENV['GOOGLE_CLOUD_PROJECT']
    client_class = configured_client.constantize
    creds_method = public_access ? :get_read_only_keyfile : :get_primary_keyfile
    service_account_credentials = client_class.send(creds_method)
    client_class.new(project:, service_account_credentials:)
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
    Rails.logger.error "Error calling #{client_method} on #{client.class}: #{e.class} - #{e.message}"
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
    Rails.logger.info "Creating study bucket #{bucket_id} for study #{study.accession}"
    client.create_study_bucket(bucket_id, location: client.location)
    Rails.logger.info "Enabling autoclass on study bucket #{bucket_id} for study #{study.accession}"
    client.enable_bucket_autoclass(bucket_id) if client.respond_to?(:enable_bucket_autoclass)
    Rails.logger.info "Setting ACLs on study bucket #{bucket_id} for study #{study.accession}"
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
    delete_study_bucket_files(client, study)
    Rails.logger.info "Deleting study bucket #{study.bucket_id} for study #{study.accession}"
    client.delete_study_bucket(study.bucket_id)
  end

  # delete specified files from a study bucket
  # can provide a file age cutoff to only delete files older than a certain date, or prefix to filter files
  #
  # * *params*
  #   - +client+ (StorageProvider) => storage client to use for deleting the files
  #   - +study+ (Study) => study for which to delete the files
  #   - +opts+ (Hash) => additional options for loading files, e.g. prefix
  #
  # * *raises*
  #   - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  #   - any exception from the client method, which will be logged and reported
  def self.delete_study_bucket_files(client, study, **opts)
    Rails.logger.info "Removing all files from study bucket #{study.bucket_id} for study #{study.accession}"
    age_cutoff = opts.delete(:file_age_cutoff) || nil
    files = client.get_study_bucket_files(study.bucket_id, **opts)
    Parallel.map(files, in_threads: 10) do |file|
      next if file.size == 0 || age_cutoff && file.created_at.in_time_zone > age_cutoff

      file.delete
    end
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
    Rails.logger.info "Assigning writer acl for study owner in #{study.accession}"
    client.update_study_bucket_acl(study.bucket_id, study.user.email, role: :writer)
    study.study_shares.each do |share|
      add_bucket_user_share(client, study, share)
    end
  end

  # set a user's share ACL for a study bucket
  #
  # * *params*
  #   - +client+ (StorageProvider) => storage client to use for updating the ACLs
  #   - +study+ (Study) => study for which to update the bucket ACLs
  #   - +share+ (StudyShare) => share to set ACL for
  #
  # * *raises*
  #   - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  #   - any exception from the client method, which will be logged and reported
  def self.add_bucket_user_share(client, study, share)
    existing_acl = client.get_study_bucket_acl(study.bucket_id)
    user_acl = "user-#{share.email}"
    role = share.permission == 'Edit' ? 'writer' : 'reader'
    acl_method = role.pluralize
    return if existing_acl.send(acl_method).include?(user_acl)

    Rails.logger.info "Assigning #{role} acl for #{share.email} in #{study.accession}"
    client.update_study_bucket_acl(study.bucket_id, share.email, role:)
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
  def self.remove_bucket_user_share(client, study, share)
    Rails.logger.info "Removing acl for share #{share.id} in #{study.accession}"
    client.update_study_bucket_acl(study.bucket_id, share.email, role: nil, delete: true)
  end

  # generate a signed URL for downloading a study file
  #
  # * *params*
  #  - +client+ (StorageProvider) => storage client to use for generating the signed URL
  #  - +study+ (Study) => study for which the file is stored
  #  - +study_file+ (StudyFile) => file to download
  #  - +expires+ (Integer) => number of seconds until the signed URL expires (default: 15)
  #
  # * *returns*
  # - +String+ => signed URL for downloading the file via browser
  #
  # * *raises*
  # - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  # - any exception from the client method, which will be logged and reported
  def self.get_signed_url(client, study, study_file, expires: 15)
    file_location = study_file.bucket_location
    call_client(client, :signed_url_for_bucket_file, study.bucket_id, file_location, expires:)
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
  def self.get_api_url(client, study, study_file)
    file_location = study_file.bucket_location
    call_client(client, :api_url_for_bucket_file, study.bucket_id, file_location)
  end

  # upload a study file to the study bucket, compressing it if needed
  # and scheduling a cleanup job to remove old versions
  #
  # * *params*
  #   - +client+ (StorageProvider) => storage client to use for uploading the file
  #   - +study+ (Study) => study for which the file is being uploaded
  #   - +study_file+ (StudyFile) => file to upload
  #
  # * *raises*
  #   - +ArgumentError+ if client is not one of ALLOWED_CLIENTS
  #   - any exception from the client method, which will be logged and reported
  def self.upload_study_file(client, study, study_file)
    identifier = "#{study_file.bucket_location}:#{study_file.id}"
    Rails.logger.info "Uploading #{identifier} to bucket #{study.bucket_id}"
    was_gzipped = FileParseService.compress_file_for_upload(study_file)
    opts = was_gzipped ? { content_encoding: 'gzip' } : {}
    remote_file = client.create_study_bucket_file(
      study.bucket_id, study_file.upload.path, study_file.bucket_location, **opts
    )
    # store generation tag to know whether a file has been updated in GCP
    Rails.logger.info "Updating #{identifier} with generation tag: #{remote_file.generation} after successful upload"
    study_file.update(generation: remote_file.generation)
    Rails.logger.info "Upload of #{identifier} complete, scheduling cleanup job"
    # schedule the upload cleanup job to run in two minutes
    run_at = 2.minutes.from_now
    Delayed::Job.enqueue(UploadCleanupJob.new(study, study_file, 0), run_at:)
    Rails.logger.info "Cleanup job for #{identifier} scheduled for #{run_at}"
  rescue *HANDLED_EXCEPTIONS => e
    ErrorTracker.report_exception(e, study.user, study, study_file, client)
    Rails.logger.error "Unable to upload #{identifier} to study bucket #{study.bucket_id}; #{e.message}"
    # notify admin of failure so they can push the file and relaunch parse
    SingleCellMailer.notify_admin_upload_fail(study_file, e).deliver_now
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
