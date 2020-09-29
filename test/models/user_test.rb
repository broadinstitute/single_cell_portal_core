require "test_helper"

class UserTest < ActiveSupport::TestCase
  def setup
    @user = User.first

    @billing_projects = [
        {'creationStatus'=>'Ready', 'projectName'=>'lab-billing-project', 'role'=>'User'},
        {'creationStatus'=>'Ready', 'projectName'=>'my-billing-project', 'role'=>'Owner'},
        {'creationStatus'=>'Ready', 'projectName'=>'my-other-billing-project', 'role'=>'Owner'}
    ]
  end

  test 'should time out token after inactivity' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @user.update_last_access_at!
    last_access = @user.api_access_token[:last_access_at]
    now = Time.now.in_time_zone(@user.get_token_timezone(:api_access_token))
    refute @user.api_access_token_timed_out?,
           "API access token should not have timed out, #{last_access} is within #{User.timeout_in} seconds of #{now}"
    # back-date access token last_access_at
    invalid_access = now - 1.hour
    @user.api_access_token[:last_access_at] = invalid_access
    @user.save
    @user.reload
    assert @user.api_access_token_timed_out?,
           "API access token should have timed out, #{invalid_access} is outside #{User.timeout_in} seconds of #{now}"
    # clean up
    @user.update_last_access_at!

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  test 'should check billing project ownership' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

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

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  test 'should assign and use metrics_uuid' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    uuid = @user.get_metrics_uuid
    @user.reload # gotcha for refreshing in-memory user object
    assert_equal uuid, @user.metrics_uuid, "Metrics UUID was not assigned correctly; #{uuid} != #{@user.metrics_uuid}"
    assigned_uuid = @user.get_metrics_uuid
    @user.reload
    assert_equal assigned_uuid, @user.metrics_uuid, "Metrics UUID has changed; #{assigned_uuid} != #{@user.metrics_uuid}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end
end
