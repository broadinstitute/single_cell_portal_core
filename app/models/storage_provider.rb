# wrapper module for including vendor-specific storage bindings
# and providing common functionality for storage providers
# e.g. AWS S3, Google Cloud Storage, etc.
#
# This module is intended to be extended by specific storage provider implementations
# that will define methods for interacting with their respective storage services,
# where this module provides a consistent interface for interacting with storage buckets
module StorageProvider
  # generic handler to call StorageService.call_client
  def call_storage_service(...)
    StorageService.call_client(...)
  end

  # create a storage bucket for a given study
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #
  # * *returns*
  #   - +Various+ => result of the API call to create the bucket
  def create_study_bucket(bucket_id)
    call_storage_service(self, :create_bucket, bucket_id)
  end

  # retrieve a storage bucket for a given study
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #
  # * *returns*
  #   - +Various+ => result of the API call to create the bucket
  def load_study_bucket(bucket_id)
    call_storage_service(self, :get_bucket, bucket_id)
  end

  # check if a storage bucket exists for a given study
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #
  # * *returns*
  #   - +Boolean+ => true if the bucket exists, false otherwise
  def bucket_exists?(bucket_id)
    # skip call_client to avoid unnecessary error logging
    get_bucket(bucket_id).present?
  end

  # create a storage bucket for a given study
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #
  # * *returns*
  #   - +Various+ => result of the API call to create the bucket
  def delete_study_bucket(bucket_id)
    call_storage_service(self, :delete_bucket, bucket_id)
  end

  # retrieve the ACL of a storage bucket
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of study bucket
  #
  # * *return*
  #   - +Various+ object representing the bucket's ACL
  def get_study_bucket_acl(bucket_id)
    call_storage_service(self, :get_bucket_acl, bucket_id)
  end

  # update the ACL of a storage bucket
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of storage bucket
  #   - +email+ (String) => email of user to update ACL for
  #   - +role+ (Symbol) => role to assign to user, e.g. :owner, :reader, :writer
  #   - +delete+ (Boolean) => whether to delete the ACL entry instead of updating it
  #
  # * *return*
  #   - +String+ => updated entity
  def update_study_bucket_acl(bucket_id, email, role: nil, delete: false)
    call_storage_service(self, :update_bucket_acl, bucket_id, email, role:, delete:)
  end

  # load all files from a study bucket
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #   - +opts+ (Hash) => extra options for the bucket_files method, such as prefix for filtering
  #
  # * *returns*
  #   - +Various+ => list of files in the bucket
  def load_study_bucket_files(bucket_id, **opts)
    call_storage_service(self, :bucket_files, bucket_id, **opts)
  end

  # upload a file to a study bucket
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #   - +remote_file+ (String) => path to file in the bucket
  #
  # * *returns*
  #  - +Various+ => result of the API call to upload the file
  def load_study_bucket_file(bucket_id, remote_file)
    call_storage_service(self, :bucket_file, bucket_id, remote_file)
  end

  # check if a study_file in a study bucket exists
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of study bucket
  #   - +filename+ (String) => name of file
  #
  # * *return*
  #   - +Boolean+
  def study_bucket_file_exists?(bucket_id, filename)
    # skip call_client to avoid unnecessary error logging
    bucket_file_exists?(bucket_id, filename)
  end

  # upload a file to a study bucket
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #   - +filepath+ (String) => path to file local file
  #   - +filename+ (String) => Name/path to use for the file in the bucket
  #   - +opts+ (Hash) => extra options for create_file
  #
  # * *returns*
  #  - +Various+ => result of the API call to upload the file
  def create_study_bucket_file(bucket_id, filepath, filename, **opts)
    call_storage_service(self, :create_file, bucket_id, filepath, filename, **opts)
  end

  # copy a file to a new location in a bucket
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of study bucket
  #   - +filename+ (String) => name of target file
  #   - +destination_name+ (String) => destination of new file
  #   - +opts+ (Hash) => extra options for create_file
  #
  # * *return*
  #   - +Google::Cloud::Storage::File+
  def copy_study_bucket_file(bucket_id, filename, destination_name, **opts)
    call_storage_service(self, :copy_bucket_file, bucket_id, filename, destination_name, **opts)
  end

  # delete a file in a bucket
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of study bucket
  #   - +filename+ (String) => name of file
  #
  # * *return*
  #   - +Boolean+ indication of file deletion
  def delete_study_bucket_file(bucket_id, filename)
    call_storage_service(self, :delete_bucket_file, bucket_id, filename)
  end

  # allow a file download via signed url
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #   - +filepath+ (String) => path to file in bucket
  #   - +opts+ (Hash) => extra options for generate_signed_url
  #
  # * *returns*
  #   - +String+ => signed URL for downloading the file via browser
  def download_bucket_file(bucket_id, filepath, **opts)
    call_storage_service(self, :generate_signed_url, bucket_id, filepath, **opts)
  end

  # stream a file back to the browser via a media (api) URL
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #   - +filepath+ (String) => path to file in bucket
  #
  # * *returns*
  #   - +String+ => media URL for streaming the file
  def stream_bucket_file(bucket_id, filepath)
    call_storage_service(self, :generate_api_url, bucket_id, filepath)
  end

  # read the contents of a file in a bucket into memory
  #
  # * *params*
  #  - +bucket_id+ (String) => ID of GCP bucket
  #  - +filename+ (String) => name of file
  #
  # * *return*
  # - +StringIO+ contents of file
  def read_study_bucket_file(bucket_id, filename)
    call_storage_service(self, :read_bucket_file, bucket_id, filename)
  end
end
