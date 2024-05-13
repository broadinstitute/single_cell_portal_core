# manages access to files in buckets for client-side rendering, both user-uploaded and SCP-generated
class BucketAccessService

  # default timeout for all signed URLs
  DEFAULT_TIMEOUT = 60.minutes

  def self.client
    ApplicationController.firecloud_client
  end

  # get a signed URL for a remote file in a given Study
  def self.signed_url_for(remote_file, study, user: nil)

  end

  # check if a user has direct access to the bucket
  # for performance, we do not check group shares as using signed URLs is drastically faster
  #
  # * *params*
  #   - +study+ (Study) Study where bucket lives
  #   - +user+ (User) requesting user
  #
  # * *returns*
  #   - (Boolean)
  def self.user_has_access?(study, user: nil)
    return true if study.public?

    study.user == user || study.study_shares.non_reviewers.map(&:downcase).include?(user.email.downcase)
  end

  # determine if a remote file is available
  #
  # * *params*
  #   - +remote_file+ (String) path to file in a bucket
  #   - +study+ (Study) Study where bucket lives
  #
  # * *returns*
  #   - (Boolean)
  def self.remote_exists?(remote_file, study)
    client.workspace_file_exists?(study.bucket_id, remote_file)
  end
end
