# wrapper module for including vendor-specific storage bindings
# and providing common functionality for storage providers
# e.g. AWS S3, Google Cloud Storage, etc.
#
# This module is intended to be extended by specific storage provider implementations
# that will define methods for interacting with their respective storage services.
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
    StorageService.call_client(self, :bucket, bucket_id)
  end
end
