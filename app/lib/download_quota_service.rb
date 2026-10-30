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

    user_quota = user.daily_download_quota + requested_bytes.to_i
    user_quota > download_quota
  end

  # add downloaded file sizes to user daily quota
  def self.increment_user_quota(user, requested_bytes)
    # skip incrementing quota if exemption is set via nil value
    return true if user.daily_download_quota.nil?

    user_quota = user.daily_download_quota + requested_bytes.to_i
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

  # return number of GB in excess of quota for a user if they were to download requested bytes
  def self.gb_in_excess_of_quota(user, requested_bytes)
    return 0 if user.daily_download_quota.nil?

    # if user is already over quota, only count the requested bytes toward the excess
    user_quota = user.daily_download_quota >= download_quota ? requested_bytes.to_i : user.daily_download_quota + requested_bytes.to_i
    excess_bytes = user_quota - download_quota
    if excess_bytes.positive?
      (excess_bytes / 1024 / 1024 / 1024.0).ceil # always round up to next GB
    else
      0
    end
  end  

  # create a checkout session for the user to pay for the excess data egress
  def self.data_egress_checkout(user, gb_excess, file_info)
    client = StripeApiClient.new
    egress_product = client.products.detect { |p| p.name == 'Data Egress Charge' }
    raise StandardError, 'Data Egress Charge product not found in Stripe' if egress_product.nil?

    client.create_data_egress_checkout_session(
      egress_product.id, user, gb_excess, file_info
    )
  end

  # mark a purchase as fulfilled for a user once they download the requested item
  # this allows the user to download the requested data
  def self.fulfill_egress_purchase(user, download_identifier, requested_bytes)
    purchase = Purchase.find_by(download_identifier:, customer_email: user.email, fulfilled: false)

    # mark the purchase as fulfilled
    purchase.update(fulfilled: true)
    increment_user_quota(user, requested_bytes)
  end
end
