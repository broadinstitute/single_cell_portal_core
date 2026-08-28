# manage anonymous access to private studies via access code & pin
# will generate a short-lived session for reviewers with valid credentials
class ReviewerAccess
  include Mongoid::Document
  include Mongoid::Timestamps
  include ActiveSupport::SecurityUtils

  field :access_code, type: String # UUID
  field :pin, type: String # 10 character string
  field :expires_at, type: Date, default: 2.months.from_now.to_date

  PIN_LENGTH = 10
  # regex to strip all non-alphanumeric characters from a user-supplied pin value
  PIN_SANITIZER = /(\W|_)/.freeze

  belongs_to :study
  has_many :reviewer_access_sessions, dependent: :delete_all do
    def by_session_key(session_key = '')
      return nil if session_key.nil?

      sanitized_key = session_key[0...36].to_s
      UUID.validate(sanitized_key) ? find_by(session_key: sanitized_key) : nil
    end
  end

  before_validation :generate_credentials, on: :create
  validates :access_code, :pin, :expires_at, presence: true
  validates :study_id, uniqueness: true, presence: true

  # determine if user-supplied pin is valid
  def authenticate_pin?(pin_value)
    begin
      fixed_length_secure_compare(pin, sanitize_pin(pin_value))
    rescue ArgumentError
      false
    end
  end

  # user-readable timestamp
  def expiration_date
    expires_at.to_fs(:long)
  end

  # check if access has expired (date-inclusive)
  def expired?
    Time.zone.today > expires_at
  end

  # determine if a specified ReviewerAccessSession is still valid
  # will default to false if session_key is not found
  def session_valid?(session_key)
    session = reviewer_access_sessions.by_session_key(session_key)
    session.present? ? !session.expired? : false
  end

  # set the cookie name, since we can't specify a :path value for the cookie
  # this ensures the cookie is only read for the corresponding study, and allows a reviewer access to multiple studies,
  # if access has been granted
  def cookie_name
    "reviewer_session_#{study.accession}".to_sym
  end

  # rotate access credentials by generating a new access_code and pin, will also clear out all reviewer sessions
  def rotate_credentials!
    clear_all_reviewer_sessions!
    generate_credentials
    save!
  end

  # create a new session and return
  def create_new_session
    session = reviewer_access_sessions.build
    session.save!
    session
  end

  # invalidate all reviewer sessions (generally when rotating credentials)
  def clear_all_reviewer_sessions!
    reviewer_access_sessions.delete_all
  end

  private

  def generate_credentials
    self.access_code = SecureRandom.uuid
    self.pin = SecureRandom.alphanumeric(PIN_LENGTH).upcase
  end

  def sanitize_pin(unsafe_pin)
    unsafe_pin.gsub(PIN_SANITIZER, '').chars.take(PIN_LENGTH).join
  end
end
