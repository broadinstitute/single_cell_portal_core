require 'test_helper'

class UserTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @user.update(registered_for_firecloud: true) # for billing projects test
    @existing_access_token = @user.access_token
    @existing_api_token = @user.api_access_token
    @user.update_last_access_at!
    @billing_projects = [
        {'creationStatus'=>'Ready', 'projectName'=>'lab-billing-project', 'role'=>'User'},
        {'creationStatus'=>'Ready', 'projectName'=>'my-billing-project', 'role'=>'Owner'},
        {'creationStatus'=>'Ready', 'projectName'=>'my-other-billing-project', 'role'=>'Owner'}
    ]
  end

  teardown do
    # reset user tokens
    @user.update(access_token: @existing_access_token, api_access_token: @existing_api_token, refresh_token: nil)
    @user.update_last_access_at!
  end

  test 'should time out token after inactivity' do
    @user.update_last_access_at!
    last_access = @user.api_access_token[:last_access_at]
    now = Time.now.in_time_zone(@user.get_token_timezone(:api_access_token))
    assert_not @user.api_access_token_timed_out?,
               "API access token should not have timed out, #{last_access} is within #{@user.timeout_in} seconds of #{now}"
    # back-date access token last_access_at for 24h session
    invalid_access = now - 25.hours
    @user.api_access_token[:last_access_at] = invalid_access
    @user.save
    assert @user.api_access_token_timed_out?,
           "API access token should have timed out, #{invalid_access} is outside #{@user.timeout_in} seconds of #{now}"
    # test short session timeout at 15m
    @user.update_last_access_at!
    assert_not @user.api_access_token_timed_out?
    @user.update(use_short_session: true)
    invalid_access = now - 20.minutes
    @user.api_access_token[:last_access_at] = invalid_access
    @user.save
    assert @user.api_access_token_timed_out?,
           "API access token should have timed out, #{invalid_access} is outside #{@user.timeout_in} seconds of #{now}"
  end

  test 'should check billing project ownership' do
    # assert user is 'Owner', using mock as we have no actual user in Terra or OAuth token to make API call
    mock = Minitest::Mock.new
    mock.expect :get_billing_projects, @billing_projects

    FireCloudClient.stub :new, mock do
      project = 'my-billing-project'
      is_owner = @user.is_billing_project_owner?(project)
      mock.verify
      assert is_owner, "Did not correctly return true for ownership of #{project}: #{@billing_projects}"
    end

    # refute user is 'Owner'
    negative_mock = Minitest::Mock.new
    negative_mock.expect :get_billing_projects, @billing_projects

    FireCloudClient.stub :new, negative_mock do
      project = 'lab-billing-project'
      is_owner = @user.is_billing_project_owner?(project)
      negative_mock.verify
      refute is_owner, "Did not correctly return false for ownership of #{project}: #{@billing_projects}"
    end
  end

  test 'should assign and use metrics_uuid' do
    uuid = @user.get_metrics_uuid
    @user.reload # gotcha for refreshing in-memory user object
    assert_equal uuid, @user.metrics_uuid, "Metrics UUID was not assigned correctly; #{uuid} != #{@user.metrics_uuid}"
    assigned_uuid = @user.get_metrics_uuid
    @user.reload
    assert_equal assigned_uuid, @user.metrics_uuid, "Metrics UUID has changed; #{assigned_uuid} != #{@user.metrics_uuid}"
  end

  test 'should return empty access token after timeout/logout' do
    assert_equal @existing_access_token.dig(:access_token), @user.valid_access_token.dig(:access_token)
    assert_equal @existing_api_token.dig(:access_token), @user.token_for_api_call.dig(:access_token)

    # clear tokens to test default response
    @user.update(access_token: nil, api_access_token: nil)
    empty_response = {}
    assert_equal empty_response, @user.valid_access_token
    assert_equal empty_response, @user.token_for_api_call
  end

  test 'should handle errors when generating pet service account token' do
    # assign mock refresh token first
    @user.update(refresh_token: @user.access_token.dig('access_token'))

    # user does not actually have a Terra profile which will throw an error
    # RuntimeError should be handled and not raised here
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Pet Service Account Token Test', user: @user, test_array: @@studies_to_clean)
    assert_nothing_raised do
      token = @user.token_for_storage_object(study)
      assert_nil token
    end
  end

  test 'should determine if user needs to accept updated Terra Terms of Service' do
    mock = Minitest::Mock.new
    user_registration = {
      enabled: {
        ldap: true,
        allUsersGroup: true,
        google: true,
        tosAccepted: true,
        adminEnabled: false
      },
      userInfo: {
        userEmail: @user.email,
        userSubjectId: @user.uid
      }
    }.with_indifferent_access
    mock.expect :get_registration, user_registration
    FireCloudClient.stub :new, mock do
      assert_not @user.must_accept_terra_tos?
      mock.verify
    end

    # negative test
    user_registration[:enabled][:tosAccepted] = false
    mock = Minitest::Mock.new
    mock.expect :get_registration, user_registration
    FireCloudClient.stub :new, mock do
      assert @user.must_accept_terra_tos?
      mock.verify
    end

    # failover test
    user_registration[:enabled].delete(:tosAccepted)
    mock = Minitest::Mock.new
    mock.expect :get_registration, user_registration
    FireCloudClient.stub :new, mock do
      assert_not @user.must_accept_terra_tos?
      mock.verify
    end
  end
end
