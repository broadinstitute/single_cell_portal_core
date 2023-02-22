require 'test_helper'

class AbTestAssignmentTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @feature_flag = FeatureFlag.find_or_create_by!(name: 'explore_tab_default')
    @ab_test = AbTest.create(feature_flag: @feature_flag)
    @assignment = @ab_test.assignment(@user.metrics_uuid)
  end

  teardown do
    @user.feature_flag_options.destroy_all
  end

  after(:all) do
    @feature_flag.destroy
  end

  test 'should only create one session per flag per user' do
    assert_equal @user.metrics_uuid, @assignment.metrics_uuid
    assert_equal @user.id, @assignment.user.id
    assert_raise Mongoid::Errors::Validations do
      AbTestAssignment.create!(ab_test: @ab_test, feature_flag: @feature_flag, metrics_uuid: @user.metrics_uuid)
    end
  end

  test 'should find ab test assigment by metrics uuid' do
    loaded_assignment = @ab_test.assignment(@user.metrics_uuid)
    assert_equal @assignment.metrics_uuid, loaded_assignment.metrics_uuid
    assert_equal @assignment.id, loaded_assignment.id
  end

  test 'should set session tag' do
    expected_name = "explore-tab-default-group-#{@assignment.group_name}"
    assert_equal expected_name, @assignment.tag
  end

  test 'should find flag override, if present' do
    assert_not @assignment.flag_override?
    @user.set_flag_option(@feature_flag.name, true)
    assert @assignment.flag_override?
  end
end
