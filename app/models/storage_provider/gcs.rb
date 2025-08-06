# Google Cloud Storage client for managing files in GCS buckets.
module StorageProvider
  class Gcs
    include StorageProvider
    extend ::ServiceAccountManager
    include ::GoogleServiceClient
    include ::ApiHelpers

    attr_accessor :project, :storage, :service_account_credentials

    ACL_ROLES = %w[reader writer owner].freeze
    GOOGLE_SCOPES = %w[
      https://www.googleapis.com/auth/userinfo.profile
      https://www.googleapis.com/auth/userinfo.email
      https://www.googleapis.com/auth/devstorage.read_only
    ].freeze

    # Default constructor for GcsClient
    #
    # * *params*
    #   - +project+: (String) => GCP Project number to use (can be overridden by other parameters)
    #   - +service_account_credentials+: (Path) => Absolute filepath to service account credentials
    # * *return*
    #   - +StorageProvider::GcsClient+
    def initialize(project: self.class.compute_project, service_account_credentials: self.class.get_primary_keyfile)
      storage_attr = {
        project_id: project,
        timeout: 3600,
        credentials: service_account_credentials
      }

      self.project = project
      self.service_account_credentials = service_account_credentials
      self.storage = Google::Cloud::Storage.new(**storage_attr)
    end

    # list available GCS buckets in the project
    #
    # * *returns*
    #   - +Array<Google::Cloud::Storage::Bucket>+ => array of GCS buckets in the project
    delegate :buckets, to: :storage

    # create a GCS bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCS bucket
    #   - +opts+ (Hash) => hash of optional params
    #
    # * *return*
    #   - +Google::Cloud::Storage::Bucket+ object
    delegate :create_bucket, to: :storage

    # retrieve a GCS bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCS bucket
    #
    # * *return*
    #   - +Google::Cloud::Storage::Bucket+ object
    def get_bucket(bucket_id)
      storage.bucket(bucket_id)
    end

    # delete a GCS bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCS bucket
    def delete_bucket(bucket_id)
      get_bucket(bucket_id)&.delete
    end

    # retrieve the ACL of a GCS bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCS bucket
    #
    # * *return*
    #   - +Google::Cloud::Storage::Acl+ object representing the bucket's ACL
    def get_bucket_acl(bucket_id)
      study_bucket = get_bucket(bucket_id)
      study_bucket.acl
    end

    # update the ACL of a GCS bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCS bucket
    #   - +email+ (String) => email of user to update ACL for
    #   - +role+ (Symbol) => role to assign to user, e.g. :owner, :reader, :writer
    #   - +delete+ (Boolean) => whether to delete the ACL entry instead of updating it
    #
    # * *return*
    #   - (String) => updated entity
    def update_bucket_acl(bucket_id, email, role: nil, delete: false)
      raise ArgumentError unless ACL_ROLES.include?(role.to_s) || (role.nil? && delete)

      bucket_acl = get_bucket_acl(bucket_id)
      acl_method = delete ? :delete : "add_#{role}".to_sym
      bucket_acl.send(acl_method, "user-#{email}")
    end

    # turn on the autoclass feature for a GCS bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCS bucket
    #   - +terminal_storage_class+ (Symbol) => storage class to use for terminal files, e.g. 'NEARLINE', 'ARCHIVE'
    def enable_bucket_autoclass(bucket_id, terminal_storage_class: 'ARCHIVE')
      study_bucket = get_bucket(bucket_id)
      study_bucket.update_autoclass(enabled: true, terminal_storage_class:)
    end

    # retrieve all files in a GCP bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCP bucket
    #   - +opts+ (Hash) => hash of optional parameters
    #
    # * *return*
    #   - +Google::Cloud::Storage::File::List+
    def bucket_files(bucket_id, **opts)
      study_bucket = get_bucket(bucket_id)
      study_bucket.files(**opts)
    end

    # retrieve single study_file in a GCP bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCP bucket
    #   - +filename+ (String) => name of file
    #
    # * *return*
    #   - +Google::Cloud::Storage::File+
    def bucket_file(bucket_id, filename)
      study_bucket = get_bucket(bucket_id)
      study_bucket.file filename
    end

    # check if a study_file in a GCP bucket exists
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of study GCP bucket
    #   - +filename+ (String) => name of file
    #
    # * *return*
    #   - +Boolean+
    def bucket_file_exists?(bucket_id, filename)
      file = bucket_file(bucket_id, filename)
      file.present?
    rescue Google::Apis::Error
      false
    end

    # add a file to a bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of study GCP bucket
    #   - +filepath+ (String) => path to file
    #   - +filename+ (String) => name of file
    #   - +opts+ (Hash) => extra options for create_file
    #
    # * *return*
    #   - +Google::Cloud::Storage::File+
    def create_bucket_file(bucket_id, filepath, filename, **opts)
      study_bucket = get_bucket(bucket_id)
      study_bucket.create_file(filepath, filename, **opts)
    end

    # copy a file to a new location in a bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCP bucket
    #   - +filename+ (String) => name of target file
    #   - +destination_name+ (String) => destination of new file
    #   - +opts+ (Hash) => extra options for create_file
    #
    # * *return*
    #   - +Google::Cloud::Storage::File+
    def copy_bucket_file(bucket_id, filename, destination_name, **opts)
      file = bucket_file(bucket_id, filename)
      file.copy(destination_name, **opts)
    end

    # delete a file in a bucket
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCP bucket
    #   - +filename+ (String) => name of file
    #
    # * *return*
    #   - +Boolean+ indication of file deletion
    def delete_bucket_file(bucket_id, filename)
      file = bucket_file(bucket_id, filename)
      file.delete
    end

    # read the contents of a file in a bucket into memory
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCP bucket
    #   - +filename+ (String) => name of file
    #
    # * *return*
    #   - +StringIO+ contents of file
    def read_bucket_file(bucket_id, filename)
      file = bucket_file(bucket_id, filename)
      file_contents = file.download
      file_contents.rewind
      file_contents
    end

    # generate a signed url to download a file that isn't public (set at study level)
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCP bucket
    #   - +filename+ (String) => name of file
    #   - +...+ (Hash) => extra options for signed_url, such as expires: or :headers
    #
    # * *return*
    #   - +String+ signed URL
    def generate_signed_url(bucket_id, filename, ...)
      file = bucket_file(bucket_id, filename)
      file.signed_url(...)
    end

    # generate an api url to directly load a file from GCS via client-side JavaScript
    #
    # * *params*
    #   - +bucket_id+ (String) => ID of GCP bucket
    #   - +filename+ (String) => name of file
    #
    # * *return*
    #   - +String+ signed URL
    def generate_api_url(bucket_id, filename)
      file = bucket_file(bucket_id, filename)
      file.api_url
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

      error.try(:status_code) || error.try(:code) || 500
    end
  end
end
