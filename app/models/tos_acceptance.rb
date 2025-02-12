class TosAcceptance
  include Mongoid::Document
  include Mongoid::Timestamps

  CURRENT_VERSION = Date.parse('2025-01-15') # current revision of ToS

  field :email, type: String
  field :version, type: Date, default: CURRENT_VERSION

  validates_presence_of :email, :version
  validates_uniqueness_of :email, scope: :version, message: "The requested user has already accepted the Terms of Service."

  # determine if a user has accepted the ToS
  def self.accepted?(user)
    self.where(email: user.email, version: CURRENT_VERSION).exists?
  end

  # string date representation of current version
  def self.current_version
    CURRENT_VERSION.strftime("%-m.%d.%y")
  end
end
