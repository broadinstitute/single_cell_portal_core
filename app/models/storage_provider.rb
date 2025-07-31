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
  #   - (Various) => result of the API call to create the bucket
  def create_study_bucket(bucket_id)
    StorageService.call_client(self, :create_bucket, bucket_id)
  end

  # retrieve a storage bucket for a given study
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #
  # * *returns*
  #   - (Various) => result of the API call to create the bucket
  def load_study_bucket(bucket_id)
    StorageService.call_client(self, :get_bucket, bucket_id)
  end

  # load all files from a study bucket
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #   - +opts+ (Hash) => extra options for the bucket_files method, such as prefix for filtering
  #
  # * *returns*
  #   - (Various) => list of files in the bucket
  def load_study_bucket_files(bucket_id, **opts)
    StorageService.call_client(self, :bucket_files, bucket_id, **opts)
  end

  # allow a file download via signed url
  #
  # * *params*
  #   - +bucket_id+ (String) => ID of bucket
  #   - +filepath+ (String) => path to file in bucket
  #   - +opts+ (Hash) => extra options for generate_signed_url
  #
  # * *returns*
  #   - (String) => signed URL for downloading the file via browser
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
  #   - (String) => media URL for streaming the file
  def stream_bucket_file(bucket_id, filepath)
    StorageService.call_client(self, :generate_api_url, bucket_id, filepath)
  end
end
