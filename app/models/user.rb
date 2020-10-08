require 'rest-client'

class User

  ###
  #
  # User: class storing information regarding Google-based email accounts.
  #
  ###

  include Mongoid::Document
  include Mongoid::Timestamps
  include FeatureFlaggable
  extend ErrorTracker

  ###
  #
  # SCOPES & FIELD DEFINITIONS
  #
  ###

  has_many :studies
  has_many :branding_groups

  # User annotations are owned by a user
  has_many :user_annotations do
    def owned_by(user)
      where(user_id: user.id, queued_for_deletion: false).select {|ua| ua.valid_annotation?}
    end
  end


  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable,
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable, :timeoutable,
         :omniauthable, :omniauth_providers => [:google_oauth2]

  validates_format_of :email, :with => Devise.email_regexp, message: 'is not a valid email address.'

  ## Database authenticatable
  field :email,              type: String, default: ""
  field :encrypted_password, type: String, default: ""

  ## Recoverable
  field :reset_password_token,   type: String
  field :reset_password_sent_at, type: Time

  ## Rememberable
  field :remember_created_at, type: Time

  ## Trackable
  field :sign_in_count,      type: Integer, default: 0
  field :current_sign_in_at, type: Time
  field :last_sign_in_at,    type: Time
  field :current_sign_in_ip, type: String
  field :last_sign_in_ip,    type: String

  ## OmniAuth
  field :uid,       type: String
  field :provider,  type: String

  # token auth for AJAX calls
  field :authentication_token, type: String

  # Google OAuth refresh token fields
  field :refresh_token, type: Mongoid::EncryptedString
  field :access_token, type: Hash # from Google OAuth callback

  # Used for time-based one-time access token (TOTAT)
  field :totat, type: Integer

# Time (t) and time interval (ti) for the TOTAT
  field :totat_t_ti, type: String

  ## Confirmable
  # field :confirmation_token,   type: String
  # field :confirmed_at,         type: Time
  # field :confirmation_sent_at, type: Time
  # field :unconfirmed_email,    type: String # Only if using reconfirmable

  ## Lockable
  # field :failed_attempts, type: Integer, default: 0 # Only if lock strategy is :failed_attempts
  # field :unlock_token,    type: String # Only if unlock strategy is :email or :both
  # field :locked_at,       type: Time

  ## Custom
  field :admin, type: Boolean
  field :reporter, type: Boolean
  field :daily_download_quota, type: Integer, default: 0
  field :admin_email_delivery, type: Boolean, default: true
  field :registered_for_firecloud, type: Boolean, default: false
  # {
  #   access_token: String OAuth token,
  #   expires_in: Integer duration in seconds,
  #   expires_at: DateTime expiry timestamp,
  #   last_access_at: DateTime last usage of token
  # }
  field :api_access_token, type: Hash
  field :metrics_uuid, type: String

  # feature_flags should be a hash of true/false values.  If unspecified for a given flag, the
  # default_value from the FeatureFlag should be used.  Accordingly, the helper method feature_flags_with_defaults
  # is provided
  field :feature_flags, type: Hash, default: {}

  ###
  #
  # OAUTH2 METHODS
  #
  ###

  def self.from_omniauth(access_token)
    data = access_token.info
    provider = access_token.provider
    uid = access_token.uid
    # create bogus password, Devise will never use it to authenticate
    password = Devise.friendly_token[0,20]
    user = User.find_by(email: data['email'])
    if user.nil?
      user = User.create(email: data["email"],
                         password: password,
                         password_confirmation: password,
                         uid: uid,
                         provider: provider)

    elsif user.provider.nil? || user.uid.nil?
      # update info if account was originally local but switching to Google auth
      user.update(provider: provider, uid: uid)
    end
    # store refresh token
    if !access_token.credentials.refresh_token.nil?
      user.update(refresh_token: access_token.credentials.refresh_token)
    end
    user
  end

  # generate an access token based on user's refresh token
  def generate_access_token
    unless self.refresh_token.nil?
      begin
        client = Signet::OAuth2::Client.new(
            token_credential_uri: 'https://accounts.google.com/o/oauth2/token',
            grant_type:'refresh_token',
            refresh_token: self.refresh_token,
            client_id: ENV['OAUTH_CLIENT_ID'],
            client_secret: ENV['OAUTH_CLIENT_SECRET'],
            expires_in: 3600
        )
        token_vals = client.fetch_access_token
        expires_at = Time.zone.now + token_vals['expires_in'].to_i.seconds
        user_access_token = {'access_token' => token_vals['access_token'], 'expires_in' => token_vals['expires_in'], 'expires_at' => expires_at}
        self.update!(access_token: user_access_token)
        user_access_token
      rescue => e
        ErrorTracker.report_exception(e, self)
        Rails.logger.error "#{Time.zone.now}: Unable to generate access token for user #{self.email} due to error; #{e.message}"
        nil
      end
    else
      Rails.logger.error "#{Time.zone.now}: Unable to generate access token for user #{self.email} due to missing refresh token"
      nil
    end
  end

  # check timestamp on user access token expiry
  def access_token_expired?
    self.access_token.nil? ? true : Time.at(self.access_token[:expires_at]) < Time.now.in_time_zone(self.get_token_timezone(:access_token))
  end

  def api_access_token_expired?
    self.api_access_token.nil? ? true : Time.at(self.api_access_token[:expires_at]) < Time.now.in_time_zone(self.get_token_timezone(:api_access_token))
  end

  # check if an API access token has 'timed out' due to no usage in the last 30 minutes
  def api_access_token_timed_out?
    if self.api_access_token.nil?
      true
    else
      # if token has been used in last 30 min (User.timeout_in), then timestamp + timeout_in > now
      # therefore, make sure last_access + timeout_in is in the future
      last_access = self.api_access_token[:last_access_at]
      last_access.present? ? (last_access + self.timeout_in) < Time.now.in_time_zone(self.get_token_timezone(:api_access_token)) : true
    end
  end

  # refresh API token last_access_at, if token is present
  def update_last_access_at!
    if self.api_access_token.present?
      self.api_access_token[:last_access_at] = Time.now.in_time_zone(self.get_token_timezone(:api_access_token))
      self.save
    end
  end

  # return an valid access token (will renew if expired) - does not apply to api access tokens, those cannot be renewed
  def valid_access_token
    self.access_token_expired? ? self.generate_access_token : self.access_token
  end

  # extract timezone from an access token to allow correct date math
  def get_token_timezone(token_method)
    self.send(token_method)[:expires_at].zone
  end

  # determine which access token is best to use for a FireCloud API request
  # once an api_access_token expires/times out, it is unset, so checking .present? will ensure a valid token
  def token_for_api_call
    if self.refresh_token.nil? && self.api_access_token.present?
      self.api_access_token
    else
      self.valid_access_token
    end
  end

  ###
  #
  # OTHER AUTHENTICATION METHODS
  #
  ###

  # Time since Unix epoch, in milliseconds
  def self.milliseconds_since_epoch
    return (Time.zone.now.to_f * 1000).round
  end

  # Creates and returns a time-based one-time access token (TOTAT).
  #
  # This isn't a password, because, after creation, it is intended for later
  # use without a username.  Instead it is an access token. For security, we
  # allow only one use of this token, and that use must be within a given
  # time interval from the creation of the token.
  #
  # Note that this TOTAT implementation is not yet intended for sensitive data.
  def create_totat(time_interval=30)
    totat = rand(999999)
    t = User.milliseconds_since_epoch()
    ti = time_interval
    t_ti = t.to_s + '_' + ti.to_s
    self.update(totat: totat)
    self.update(totat_t_ti: t_ti)
    return {'totat': totat, 'time_interval': ti}
  end

  def self.verify_totat(totat)
    user = User.find_by(totat: totat)
    if user == nil
      return false
    end
    totat_t, time_interval = user.totat_t_ti.split('_')
    current_t = User.milliseconds_since_epoch()
    # Expires TOTAT
    user.update(totat: 0)
    user.update(totat_t_ti: '')
    totat_is_fresh = current_t - totat_t.to_i <= time_interval.to_i*1000
    if totat_is_fresh
      return user
    else
      return false
    end
  end

  def get_metrics_uuid
    if self.metrics_uuid.nil?
      self.update(metrics_uuid: SecureRandom.uuid)
    end
    self.metrics_uuid
  end

  ###
  #
  # MISCELLANEOUS METHODS
  #
  ###

  # determine if user has access to reports functionality
  def acts_like_reporter?
    self.admin? || self.reporter?
  end

  # user email address as a DOM id
  def email_as_id
    self.email.gsub(/[@\.]/, '-')
  end

  # return branding groups visible to user (or all for admins)
  def available_branding_groups
    self.admin? ? BrandingGroup.all.order_by(:name.asc) : BrandingGroup.where(user_id: self.id).order_by(:name.asc)
  end

  # check if a user is registered for FireCloud and update status as necessary
  def update_firecloud_status
    if self.registered_for_firecloud
      nil
    else
      client = FireCloudClient.new(self, FireCloudClient::PORTAL_NAMESPACE)
      if client.registered?
        Rails.logger.info "#{Time.zone.now} - setting user firecloud registrations status for #{self.email} to true"
        self.update(registered_for_firecloud: true)
        self.add_to_portal_user_group
      end
    end
  end

  # retrieve billing projects for a given user (if registered for firecloud)
  def get_billing_projects
    projects = {User: [], Owner: []}
    if self.registered_for_firecloud
      client = FireCloudClient.new(self, FireCloudClient::PORTAL_NAMESPACE)
      user_projects = client.get_billing_projects
      user_projects.each do |project|
        if project['creationStatus'] == 'Ready'
          projects[project['role'].to_sym] << project['projectName']
        end
      end
    end
    projects
  end

  # return true/false if user is an owner of a given billing project
  def is_billing_project_owner?(billing_project)
    self.get_billing_projects[:Owner].include?(billing_project)
  end

  def add_to_portal_user_group
    user_group_config = AdminConfiguration.find_by(config_type: 'Portal FireCloud User Group')
    if user_group_config.present?
      group_name = user_group_config.value
      Rails.logger.info "#{Time.zone.now}: adding #{self.email} to #{group_name} user group"
      ApplicationController.firecloud_client.add_user_to_group(group_name, 'member', self.email)
      Rails.logger.info "#{Time.zone.now}: user group registration complete"
    end
  end

  # helper method to migrate study ownership & shares from old email to new email
  def self.migrate_studies_and_shares(existing_email, new_email)
    existing_user = self.find_by(email: existing_email)
    new_user = self.find_by(email: new_email)
    studies = existing_user.studies
    shares = StudyShare.where(email: existing_email).to_a
    puts "Migrating #{studies.size} studies from #{existing_email} to #{new_email}"
    studies.update_all(user_id: new_user.id)
    puts "Migrating #{shares.size} shares from #{existing_email} to #{new_email}"
    shares.update_all(email: new_email)
    puts "Migration complete"
  end
end
