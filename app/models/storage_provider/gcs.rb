# Google Cloud Storage client for managing files in GCS buckets.
module StorageProvider
  class Gcs
    include StorageProvider
    extend ::ServiceAccountManager
    include ::GoogleServiceClient
    include ::ApiHelpers

    attr_accessor :project, :service, :service_account_credentials

    GOOGLE_SCOPES = %w[email profile https://www.googleapis.com/auth/devstorage.read_only].freeze

    RETRY_BACKOFF_DENYLIST = %i[generate_signed_url generate_api_url].freeze

    ACL_ROLES = %w[reader writer owner].freeze

    # Default constructor for GcsClient
    #
    # * *params*
    #   - +project+: (String) => GCP Project number to use (can be overridden by other parameters)
    #   - +service_account_credentials+: (Path) => Absolute filepath to service account credentials
    # * *return*
    #   - +StorageProvider::GcsClient+
    def initialize(project = self.class.compute_project, service_account_credentials = self.class.get_primary_keyfile)
      storage_attr = {
        project_id: project,
        timeout: 3600,
        credentials: service_account_credentials
      }

      self.project = project
      self.service_account_credentials = service_account_credentials
      self.service = Google::Cloud::Storage.new(**storage_attr)
    end

    # create a GCS bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCS bucket
    #   - +opts+ (Hash) => hash of optional params
    #
    # * *return*
    #   - +Google::Cloud::Storage::Bucket+ object
    delegate :create_bucket, to: :service

    # retrieve a GCS bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCS bucket
    #
    # * *return*
    #   - +Google::Cloud::Storage::Bucket+ object
    delegate :bucket, to: :service

    # update the ACL of a GCS bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCS bucket
    #   - +email+ (String) => email of user to update ACL for
    #   - +role+ (Symbol) => role to assign to user, e.g. :owner, :reader, :writer
    #
    # * *return*
    #   - (String) => updated entity
    def update_bucket_acl(bucket_id, email, role)
      raise ArgumentError unless ACL_ROLES.include?(role)

      study_bucket = bucket(bucket_id)
      acl_method = "add_#{role}".to_sym
      study_bucket.send(acl_method, email)
    end

    # turn on the autoclass feature for a GCS bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCS bucket
    #   - +terminal_storage_class+ (Symbol) => storage class to use for terminal files, e.g. 'NEARLINE', 'ARCHIVE'
    def enable_bucket_autoclass(bucket_id, terminal_storage_class: 'ARCHIVE')
      study_bucket = bucket(bucket_id)
      study_bucket.update_autoclass(enabled: true, terminal_storage_class:)
    end

    # retrieve all files in a GCP bucket of a workspace
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of workspace GCP bucket
    #   - +opts+ (Hash) => hash of optional parameters
    #
    # * *return*
    #   - +Google::Cloud::Storage::File::List+
    def bucket_files(bucket_id, opts: {})
      study_bucket = bucket(bucket_id)
      study_bucket.files(**opts)
    end

    # retrieve single study_file in a GCP bucket of a workspace
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of workspace GCP bucket
    #   - +filename+ (String) => name of file
    #
    # * *return*
    #   - +Google::Cloud::Storage::File+
    def bucket_file(bucket_id, filename)
      study_bucket = bucket(bucket_id)
      study_bucket.file filename
    end

    # retrieve all files in a GCP directory
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of workspace GCP bucket
    #   - +directory+ (String) => name of directory in bucket
    #   - +opts+ (Hash) => hash of optional parameters
    #
    # * *return*
    #   - +Google::Cloud::Storage::File::List+
    def bucket_directory_files(bucket_id, directory, opts: {})
      # makes sure directory ends with '/', otherwise append to prevent spurious matches
      directory += '/' unless directory.last == '/'
      opts.merge!(prefix: directory)
      bucket_files(bucket_id, **opts)
    end

    # check if a study_file in a GCP bucket of a workspace exists
    # this method should ideally be used outside of :execute_gcloud_method to avoid unnecessary retries
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of workspace GCP bucket
    #   - +filename+ (String) => name of file
    #
    # * *return*
    #   - +Boolean+
    def bucket_file_exists?(bucket_id, filename)
      begin
        file = bucket_file(bucket_id, filename)
        file.present?
      rescue Google::Apis::Error
        false
      end
    end

    # add a file to a workspace bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of workspace GCP bucket
    #   - +filepath+ (String) => path to file
    #   - +filename+ (String) => name of file
    #   - +opts+ (Hash) => extra options for create_file
    #
    # * *return*
    #   - +Google::Cloud::Storage::File+
    def create_bucket_file(bucket_id, filepath, filename, opts: {})
      study_bucket = bucket(bucket_id)
      study_bucket.create_file(filepath, filename, **opts)
    end

    # copy a file to a new location in a workspace bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of workspace GCP bucket
    #   - +filename+ (String) => name of target file
    #   - +destination_name+ (String) => destination of new file
    #   - +opts+ (Hash) => extra options for create_file
    #
    # * *return*
    #   - +Google::Cloud::Storage::File+
    def copy_bucket_file(bucket_id, filename, destination_name, opts: {})
      file = bucket_file(bucket_id, filename)
      file.copy(destination_name, **opts)
    end

    # delete a file to a workspace bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of workspace GCP bucket
    #   - +filename+ (String) => name of file
    #
    # * *return*
    #   - +Boolean+ indication of file deletion
    def delete_bucket_file(bucket_id, filename)
      file = bucket_file(bucket_id, filename)
      begin
        file.delete
      rescue => e
        ErrorTracker.report_exception(
          e, issuer_object, { method_name: :delete_bucket_file, params: [bucket_id, filename] }
        )
        Rails.logger.info("failed to delete workspace file #{filename} with error #{e.message}")
        false
      end
    end

    # retrieve single file in a GCP bucket of a workspace and download locally to portal.  will perform a chunked download
    # on files larger that 50 MB
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of workspace GCP bucket
    #   - +filename+ (String) => name of file
    #   - +destination+ (String) => destination path for downloaded file
    #   - +opts+ (Hash) => extra options for signed_url
    #
    # * *return*
    #   - +File+ object
    def download_bucket_file(bucket_id, filename, destination, opts: {})
      file = bucket_file(bucket_id, filename)
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
        Rails.logger.info "Performing chunked download for #{filename} from #{bucket_id}"
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
        Rails.logger.info "Chunked download for #{filename} from #{bucket_id} complete"
        # return newly-opened file (will need to check content type before attempting to parse)
        local
      else
        file.download end_path, **opts
      end
    end

    # read the contents of a file in a workspace bucket into memory
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of workspace GCP bucket
    #   - +filename+ (String) => name of file
    #
    # * *return*
    #   - +StringIO+ contents of workspace file
    def read_bucket_file(bucket_id, filename)
      file = bucket_file(bucket_id, filename)
      file_contents = file.download
      file_contents.rewind
      file_contents
    end

    # generate a signed url to download a file that isn't public (set at study level)
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of workspace GCP bucket
    #   - +filename+ (String) => name of file
    #   - +opts+ (Hash) => extra options for signed_url
    #
    # * *return*
    #   - +String+ signed URL
    def generate_signed_url(bucket_id, filename, opts: {})
      file = bucket_file(bucket_id, filename)
      file.signed_url(**opts)
    end

    # generate an api url to directly load a file from GCS via client-side JavaScript
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of workspace GCP bucket
    #   - +filename+ (String) => name of file
    #
    # * *return*
    #   - +String+ signed URL
    def generate_api_url(bucket_id, filename)
      file = bucket_file(bucket_id, filename)
      if file
        file.api_url
      else
        ''
      end
    end

    # extract a status code from an error GCS call
    #
    # * *params*
    #   - +error+ (Google::Apis::Error) => Error from Google Cloud Storage
    #
    # * *returns*
    #   - (Integer) => HTTP status code, substituting 500 for unknown errors
    def extract_status_code(error)
      return 500 if error.is_a?(RuntimeError)

      error.try(:http_code) || error.try(:code) || 500
    end
  end
end
