require 'test_helper'

class AbTestTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @feature_flag = FeatureFlag.create(name: 'ab_test_flag')
    # random number of group names from 2-5
    limit = (2..5).to_a.sample
    group_names = 1.upto(limit).map { |i| "name-#{i}" }
    @ab_test = AbTest.create(feature_flag: @feature_flag, group_names:)
  end

  teardown do
    @ab_test.update(enabled: false)
    @ab_test.reload
    @user.feature_flag_options.destroy_all
  end

  after(:all) do
    @feature_flag.destroy
  end

  # we can't prove true random assignment, only that over a reasonable amount of iterations we would see a roughly
  # equal distribution (±2%); for reference, SCP had ~2.5K unique Study overview users/week in 2022
  test 'should distribute group assignments equally' do
    num_groups = @ab_test.group_names.size
    slice = 1.0 / num_groups
    groups = []
    n = 5_000 # simulate average 2-week test

    distribution = (slice - 0.02..slice + 0.02)
    n.times do
      groups << @ab_test.random_group
    end
    @ab_test.group_names.map do |group|
      percentage = groups.tally[group] / n.to_f
      assert distribution.include?(percentage),
             "#{group}: #{percentage} was outside ±2% distribution for #{num_groups} groups (#{slice})"
    end
  end

  test 'should load assignments for enabled tests' do
    assert_empty AbTest.load_assignments(@user.metrics_uuid)
    @ab_test.update!(enabled: true)
    assert_equal 1, AbTest.load_assignments(@user.metrics_uuid).size
    # confirm flag override removes from groups
    @user.set_flag_option(@feature_flag.name, true)
    assert_empty AbTest.load_assignments(@user.metrics_uuid)
  end

  test 'should enforce at least two groups' do
    @ab_test.group_names = %w[foo]
    assert_not @ab_test.valid?
  end

  test 'should sanitize group names' do
    existing_groups = @ab_test.group_names.dup
    @ab_test.group_names << 'has spaces'
    expected = existing_groups << 'hasspaces'
    @ab_test.valid?
    assert_equal expected, @ab_test.group_names
  end

  test 'should migrate renamed groups and unassign orphaned groups' do
    new_group = 'extra-group'
    @ab_test.group_names << new_group
    @ab_test.save!
    5.times do
      AbTestAssignment.create!(
        ab_test: @ab_test, feature_flag: @feature_flag, metrics_uuid: SecureRandom.uuid, group_name: new_group
      )
    end
    assert_equal 5, AbTestAssignment.where(
      ab_test: @ab_test, feature_flag: @feature_flag, group_name: new_group
    ).count
    # rename group
    idx = @ab_test.group_names.index(new_group)
    renamed_group = 'renamed-group'
    @ab_test.group_names[idx] = renamed_group
    @ab_test.save!
    assert_equal 5, AbTestAssignment.where(
      ab_test: @ab_test, feature_flag: @feature_flag, group_name: renamed_group
    ).count
    @ab_test.group_names.pop # remove last group
    @ab_test.save!
    assert_not AbTestAssignment.where(ab_test: @ab_test, feature_flag: @feature_flag, group_name: new_group).any?
  end
end
