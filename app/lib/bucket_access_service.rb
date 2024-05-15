# manages access to files in buckets for client-side rendering, both user-uploaded and SCP-generated
class BucketAccessService

  # default timeout for all signed URLs (1 hour, in seconds - 3600)
  DEFAULT_TIMEOUT = 1.hour.to_i

  def self.client
    ApplicationController.firecloud_client
  end

  # get a signed URL for a remote file in a given Study
  #
  # * *params*
  #   - +remote_path+ (String) path to file in a bucket
  #   - +study+ (Study) Study where bucket lives
  #
  # * *returns*
  #   - (Hash) hash with file details, including basename, size, and signed_url
  def self.signed_url_for(remote_path, study)
    remote_file = client.get_workspace_file(study.bucket_id, remote_path)
    {
      basename: remote_file.name.split('/').last,
      url: remote_file.signed_url(expires: DEFAULT_TIMEOUT, version: 'v4'),
      size: remote_file.size
    }
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
  def self.user_has_access?(study, user=nil)
    return true if study.public?
    return false if !study.public? && user.nil?

    study.user == user || study.study_shares.non_reviewers.map(&:downcase).include?(user.email.downcase)
  end

  # determine if a remote file is available
  #
  # * *params*
  #   - +remote_path+ (String) path to file in a bucket
  #   - +study+ (Study) Study where bucket lives
  #
  # * *returns*
  #   - (Boolean)
  def self.remote_exists?(remote_path, study)
    client.workspace_file_exists?(study.bucket_id, remote_path)
  end
end
