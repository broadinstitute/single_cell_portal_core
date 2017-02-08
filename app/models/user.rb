class User
  include Mongoid::Document
  include Mongoid::Timestamps

  has_many :studies

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable,
         :omniauthable, :omniauth_providers => [:google_oauth2]

  validates_format_of :email,:with => Devise.email_regexp

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
    end
    user
  end
end
