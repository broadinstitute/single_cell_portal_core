##
# DownloadAgreement: study-scope policy terms that users must accept in order to gain access to download data
# individual records of users accepting policies are tracked in DownloadAcceptance
##
class DownloadAgreement
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :study
  has_many :download_acceptances

  field :content, type: String
  field :expires_at, type: Date

  validates_presence_of :content
  validates_uniqueness_of :study_id

  # Check if an agreement has expired.  If no expiration date is present, agreement is still enforced
  def expired?
    self.expires_at.present? ? self.expires_at < Date.today : false
  end

  def user_emails
    self.download_acceptances.pluck(:email)
  end

  def user_accepted?(user)
    user.present? ? self.user_emails.include?(user.email) : false
  end

  def expiration_date
    self.expires_at || "N/A"
  end

  def accepted_count
    self.download_acceptances.count
  end
end
