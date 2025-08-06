##
# generic GCP-centric methods, such as handling authorization/tokens, or GCS drivers
# should be used in other classes via include, e.g. `include GoogleServiceClient`
##
module GoogleServiceClient
  ##
  # OAuth token methods
  ##

  # refresh access_token when expired and stores back in instance of parent class
  #
  # * *return*
  #   - +DateTime+ timestamp of new access token expiration
  def refresh_access_token!
    return valid_access_token unless respond_to?(:access_token) && respond_to?(:expires_at)

    Rails.logger.info "#{self.class.name} token expired, refreshing access token"
    # determine if token source is a regular Google account (User) or a service account
    token_source = self.respond_to?(:user) && self.user.present? ? self.user : self.class
    new_token = token_source.generate_access_token(self.service_account_credentials)
    # Add `expires_at` to `new_token`
    self.expires_at = Time.zone.now + new_token['expires_in']

    self.access_token = {
      'access_token' => new_token['access_token'],
      'expires_in' => new_token['expires_in'],
      'expires_at' => self.expires_at
    }
  end

  # check if an access_token is expired
  #
  # * *return*
  #   - +Boolean+ of token expiration
  def access_token_expired?
    return false unless respond_to?(:expires_at)

    Time.zone.now >= self.expires_at
  end

  # return a valid access token
  #
  # * *return*
  #   - +Hash+ of access token
  def valid_access_token
    if respond_to?(:expires_at)
      access_token_expired? ? refresh_access_token! : access_token
    else
      self.class.generate_access_token(service_account_credentials)
    end
  end

  ##
  # GCS Storage instance methods
  ##

  # get instance information about the storage driver
  #
  # * *return*
  #   - +JSON+ object of storage driver instance attributes
  def storage_attributes
    JSON.parse storage.to_json
  end

  # get storage driver access token
  #
  # * *return*
  #   - +String+ access token
  def storage_access_token
    storage.service.credentials.client.access_token
  end

  # get storage driver issue timestamp
  #
  # * *return*
  #   - +DateTime+ issue timestamp
  def storage_issued_at
    storage.service.credentials.client.issued_at
  end

  # get issuer of storage credentials
  #
  # * *return*
  #   - +String+ of issuer email
  def storage_issuer
    storage.service.credentials.issuer
  end

  # get issuer of access_token
  #
  # * *return*
  #   - +String+ of access_token issuer email
  def issuer
    respond_to?(:user) && user.present? ? user.email : storage_issuer
  end

  # get issuer object of access_token (either instance of User, or email of service account)
  #
  # * *return*
  #   - +User+ of access_token issuer or +String+ of service account email
  def issuer_object
    respond_to?(:user) && user.present? ? user : storage_issuer
  end
end
