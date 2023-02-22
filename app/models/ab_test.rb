# holds groups names for running A/B UI tests
# supports 2+ group assignments
class AbTest
  include Mongoid::Document
  include Mongoid::Timestamps

  has_many :ab_test_assignments, dependent: :delete_all
  belongs_to :feature_flag

  DEFAULT_GROUP_NAMES = %w[control intervention].freeze

  # regexp for sanitizing group names, all non-word characters except dashes
  NAME_SANITIZER = /[^a-zA-Z0-9_-]/

  field :group_names, type: Array, default: DEFAULT_GROUP_NAMES
  field :enabled, type: Boolean, default: false

  before_validation :sanitize_group_names
  validate :two_groups?
  after_validation :migrate_assignments, on: :update

  def random_group
    group_names.sample
  end

  def assignment(metrics_uuid)
    AbTestAssignment.find_or_create_by(feature_flag:, metrics_uuid:, ab_test: self)
  end

  def user_count(group_name)
    ab_test_assignments.where(group_name:).count
  end

  # load A/B test assignments for all enabled A/B tests using a given metrics_uuid
  # filter out any instances where the FeatureFlagOption is set as this will skew results
  def self.load_assignments(metrics_uuid)
    return [] if metrics_uuid.nil?

    where(enabled: true).map { |ab_test| ab_test.assignment(metrics_uuid) }.reject(&:flag_override?).map(&:tag)
  end

  # determine if assignment for metrics_uuid qualifies for showing an updated feature
  def override_feature?(metrics_uuid, groups: [])
    return false unless enabled

    groups.include? assignment(metrics_uuid).group_name
  end

  # determine what state a potential feature_flag and metrics_uuid combine to show
  # will consider flag default state, possible user overrides, and A/B test state
  #
  # * *params*
  #   - +flag_name+ (String)     => name of feature_flag
  #   - +metrics_uuid+ (UUID)    => value of cookies['user_id'] for current user
  #   - +groups+ (Array<String>) => array of groups that qualify to override UX (default: 'intervention')
  #
  # * *returns*
  #   - (Boolean) => T/F if current merged state constitutes an updated UX
  def self.override_for_feature?(flag_name, metrics_uuid, groups: %w[intervention])
    user = User.find_by(metrics_uuid:)
    feature_flag = FeatureFlag.find_by(name: flag_name)
    # return false if flag isn't found or A/B test is not enabled
    return false if feature_flag.blank? || !feature_flag.ab_test_enabled?

    # FeatureFlaggable#merged_value_for will check the state of feature_flag default and any user overrides
    # if that is false, then fall back to checking if user group assignment constitutes an override to the normal UX
    ab_test = feature_flag.ab_test
    FeatureFlaggable.merged_value_for(feature_flag.name, user) || ab_test.override_feature?(metrics_uuid, groups:)
  end

  private

  # ensure consistent group name formatting - all lowercase word characters (plus dashes)
  def sanitize_group_names
    group_names.map! { |name| name.gsub(NAME_SANITIZER, '').downcase }.reject!(&:blank?)
  end

  def two_groups?
    if group_names.count < 2
      errors.add(:group_names, 'must have at least two groups')
    end
  end

  # move any assignments from one group to another if a group is renamed
  # if a group is deleted it will unset all matching assignments and allow them to be randomly reassigned
  def migrate_assignments
    if group_names_changed?
      changes = group_names - group_names_was
      changes.each do |new_group|
        index = group_names.index(new_group)
        old_group = group_names_was[index]
        if old_group
          ab_test_assignments.where(group_name: old_group).update_all(group_name: new_group)
        else
          ab_test_assignments.where(group_name: old_group).delete_all
        end
      end
    end
  end
end
