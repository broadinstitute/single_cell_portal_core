require 'test_helper'
require 'integration_test_helper'
require 'includes_helper'

class AbTestsControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @admin = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    TosAcceptance.create(email: @admin.email)
    @feature_flag = FeatureFlag.find_or_create_by!(name: 'ab_test_controller_test')
  end

  setup do
    sign_in @admin
    auth_as_user @admin
  end

  teardown do
    @feature_flag.ab_test&.destroy
    @feature_flag.reload
    AbTestAssignment.destroy_all
  end

  test 'should create A/B test' do
    post create_feature_flag_ab_test_path(name: @feature_flag.name)
    follow_redirect!
    assert_equal edit_feature_flag_ab_test_path(name: @feature_flag.name), path
    assert AbTest.find_by(feature_flag: @feature_flag).present?
  end

  test 'should update A/B test' do
    AbTest.create(feature_flag: @feature_flag)
    groups = %w[control intervention combined]
    update_params = {
      ab_test: { enabled: true, group_names: groups }
    }
    patch update_feature_flag_ab_test_path(name: @feature_flag.name), params: update_params
    follow_redirect!
    ab_test = AbTest.find_by(feature_flag: @feature_flag)
    assert ab_test.enabled
    assert_equal groups, ab_test.group_names
  end

  test 'should destroy A/B test' do
    AbTest.create(feature_flag: @feature_flag)
    assert_not_nil @feature_flag.ab_test
    delete destroy_feature_flag_ab_test_path(name: @feature_flag.name)
    follow_redirect!
    assert_nil AbTest.find_by(feature_flag: @feature_flag)
  end

  test 'should add user to A/B test group' do
    ab_test = AbTest.create(feature_flag: @feature_flag)
    assert_nil AbTestAssignment.find_by(feature_flag: @feature_flag, ab_test:, metrics_uuid: @admin.metrics_uuid)
    ab_test.group_names.each do |group_name|
      @admin.set_flag_option(@feature_flag.name, true) # test clearing out flag overrides
      post add_to_ab_test_group_path(name: @feature_flag.name), params: { group_name: }
      follow_redirect!
      @admin.reload
      assert_not @admin.flag_configured?(@feature_flag.name)
      assignment = AbTestAssignment.find_by(feature_flag: @feature_flag, ab_test:, metrics_uuid: @admin.metrics_uuid)
      assert_equal group_name, assignment.group_name
    end
  end
end
