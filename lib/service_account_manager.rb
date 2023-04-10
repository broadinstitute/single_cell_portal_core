##
# class methods for loading service account keyfiles & generating OAuth2 access tokens
# should be used in other classes via extend, e.g. `extend ServiceAccountManager`
##
module ServiceAccountManager
  # generate an access token from a service account JSON keyfile
  #
  # * *params*
  #   - +service_account+ (Pathname) => path to service account JSON keyfile
  #
  # * *returns*
  #   - (Hash) => OAuth2 access token hash, with the following attributes
  #     - +access_token+ (String) => OAuth2 access token
  #     - +expires_in+ (Integer) => duration of token, in seconds
  #     - +expires_at+ (String) => timestamp of when token expires
  #     - +token_type+ (String) => type of access token (e.g. 'Bearer')
  def generate_access_token(service_account)
    creds = load_service_account_creds(service_account)
    access_token = creds.fetch_access_token!
    expires_at = Time.zone.now + access_token['expires_in']
    access_token['expires_at'] = expires_at
    access_token
  end

  # create a Google ServiceAccountCredentials instance for issuing access tokens, parsing service account attributes
  #
  # * *params*
  #   - +service_account+ (Pathname) => path to service account JSON keyfile
  #
  # * *returns*
  #   - (Google::Auth::ServiceAccountCredentials) => ServiceAccountCredentials instance
  def load_service_account_creds(service_account)
    Google::Auth::ServiceAccountCredentials.make_creds(
      {
        scope: self::GOOGLE_SCOPES,
        json_key_io: File.open(service_account)
      }
    )
  end

  # return the GCP project this instance is running in
  def compute_project
    ENV['GOOGLE_CLOUD_PROJECT']
  end

  # resolve filepath to primary service account (e.g. project owner) keyfile
  def get_primary_keyfile
    ENV['NOT_DOCKERIZED'] ? ENV['SERVICE_ACCOUNT_KEY'] : File.absolute_path(ENV['SERVICE_ACCOUNT_KEY'])
  end

  # resolve filepath to primary service account (e.g. project owner) keyfile
  def get_read_only_keyfile
    ENV['NOT_DOCKERIZED'] ? ENV['READ_ONLY_SERVICE_ACCOUNT_KEY'] : File.absolute_path(ENV['READ_ONLY_SERVICE_ACCOUNT_KEY'])
  end
end
