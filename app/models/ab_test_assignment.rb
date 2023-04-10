# reference document to map a user/metrics_uuid to a feature_flag A/B test group
class AbTestAssignment
  include ::Mongoid::Document
  include ::Mongoid::Timestamps

  belongs_to :feature_flag
  belongs_to :ab_test
  belongs_to :user, optional: true, foreign_key: :metrics_uuid, primary_key: :metrics_uuid

  field :metrics_uuid, type: String, overwrite: true
  field :group_name, type: String

  validates :metrics_uuid, uniqueness: { scope: :feature_flag_id }, presence: true
  validates :group_name, presence: true
  before_validation :assign_group, on: :create, if: proc { group_name.blank? }

  delegate :random_group, to: :ab_test

  def tag
    "#{feature_flag.name.dasherize}-group-#{group_name}".downcase
  end

  # determine if a user has a FeatureFlagOption override in place
  # this would override what happens in the UI so we need to account for this when reporting groups
  def flag_override?
    user.nil? ? false : user.flag_configured?(feature_flag.name)
  end

  private

  def assign_group
    self.group_name = random_group
  end
end
