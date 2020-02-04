require "integration_test_helper"

class AdminConfigurationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  # this test creates its own user since it needs to modify it as part of the test
  def setup
    @test_user = User.create(email: 'test_flags_user@gmail.com',
                             password: 'password',
                             password_confirmation: 'password')
  end

  def teardown
    User.find_by(email: 'test_flags_user@gmail.com').destroy
  end

  test 'should process feature flag data correctly' do
    @test_user.update!(feature_flags: {})

    AdminConfigurationsController.process_feature_flag_form_data(@test_user, {feature_flag_faceted_search: '1'})
    assert_equal({'faceted_search' => true}, @test_user.reload.feature_flags)

    AdminConfigurationsController.process_feature_flag_form_data(@test_user, {feature_flag_faceted_search: '0'})
    assert_equal({'faceted_search' => false}, @test_user.reload.feature_flags)

    AdminConfigurationsController.process_feature_flag_form_data(@test_user, {faceted_search: '-'})
    assert_equal({}, @test_user.reload.feature_flags)
  end
end
