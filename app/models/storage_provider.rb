# wrapper module for including vendor-specific storage bindings
# and providing common functionality for storage providers
# e.g. AWS S3, Google Cloud Storage, etc.
#
# This module is intended to be extended by specific storage provider implementations
# that will define methods for interacting with their respective storage services,
# where this module provides a consistent interface for interacting with storage buckets
module StorageProvider
  # create a storage bucket for a given study
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #
  # * *returns*
  #   - +Various+ => result of the API call to create the bucket
  def create_study_bucket(bucket_id)
    StorageService.call_client(self, :create_bucket, bucket_id)
  end

  # retrieve a storage bucket for a given study
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #
  # * *returns*
  #   - +Various+ => result of the API call to create the bucket
  def load_study_bucket(bucket_id)
    StorageService.call_client(self, :get_bucket, bucket_id)
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
    StorageService.call_client(self, :delete_bucket, bucket_id)
  end

  # retrieve the ACL of a storage bucket
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of study bucket
  #
  # * *return*
  #   - +Various+ object representing the bucket's ACL
  def get_study_bucket_acl(bucket_id)
    StorageService.call_client(self, :get_bucket_acl, bucket_id)
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
    StorageService.call_client(self, :update_bucket_acl, bucket_id, email, role:, delete:)
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
    StorageService.call_client(self, :bucket_files, bucket_id, **opts)
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
    StorageService.call_client(self, :create_file, bucket_id, filepath, filename, opts)
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
  def download_bucket_file(bucket_id, filepath, opts: {})
    StorageService.call_client(self, :generate_signed_url, bucket_id, filepath, opts)
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
    StorageService.call_client(self, :generate_api_url, bucket_id, filepath)
  end
end
