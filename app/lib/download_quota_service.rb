# consolidate actions for dealing with daily download quotas for users
class DownloadQuotaService
  # error message to instruct users to email Zendesk for temporary quota exceptions
  QUOTA_HELP_EMAIL = 'Please try again tomorrow after it resets, or email ' \
                     '<a href="mailto:scp-support@zendesk.com">scp-support@zendesk.com</a> if you require ' \
                     'immediate assistance to request a temporary quota exemption.'.freeze
  # daily reset of user quotas
  def self.reset_all_quotas
    User.update_all(daily_download_quota: 0)
  end

  # grant a download quota exemption for a user
  # setting daily_download_quota to nil will prevent any downloads from being added to their quota
  def self.grant_user_exemption(user)
    user.update(daily_download_quota: nil)
  end

  # check if a potential download will exceed a user's quota
  def self.download_exceeds_quota?(user, requested_bytes)
    return false if user.daily_download_quota.nil?

    user_quota = user.daily_download_quota + requested_bytes
    user_quota > download_quota
  end

  # add downloaded file sizes to user daily quota
  def self.increment_user_quota(user, requested_bytes)
    # skip incrementing quota if exemption is set via nil value
    return true if user.daily_download_quota.nil?

    user_quota = user.daily_download_quota + requested_bytes
    user.update(daily_download_quota: user_quota)
  end

  # retrieve download quota value as set in AdminConfiguration
  def self.download_quota
    config_entry = AdminConfiguration.find_by(config_type: 'Daily User Download Quota')
    if config_entry.nil? || config_entry.value_type != 'Numeric'
      # fallback in case entry cannot be found or is set to wrong type
      2.terabytes
    else
      config_entry.convert_value_by_type
    end
  end
end
