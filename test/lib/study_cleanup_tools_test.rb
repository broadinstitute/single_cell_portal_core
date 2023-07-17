require 'test_helper'

# test all validations to ensure security is being enforced that will block accidental deletes of user studies/workspaces
# does not directly test cleanup methods as these would destroy seed data needed for other tests
class StudyCleanupToolsTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'Cleanup Security Checks',
                                     user: @user,
                                     test_array: @@studies_to_clean)
  end

  test 'should validate hostname' do
    assert StudyCleanupTools.permit_hostname?

    # negative test, stub hostname
    Socket.stub :gethostname, 'singlecell.broadinstitute.org' do
      refute StudyCleanupTools.permit_hostname?
    end
  end

  test 'should validate billing project' do
    billing_project = FireCloudClient::PORTAL_NAMESPACE
    assert StudyCleanupTools.permit_billing_project?(billing_project)

    bad_project = "this-is-not-valid"
    refute StudyCleanupTools.permit_billing_project?(bad_project)
  end

  test 'should validate environment' do
    assert StudyCleanupTools.permit_environment?

    # test allowing development environment
    dev_mock = Minitest::Mock.new
    dev_mock.expect :test?, false
    dev_mock.expect :pentest?, false
    dev_mock.expect :development?, true

    Rails.stub :env, dev_mock do
      assert StudyCleanupTools.permit_environment?(allow_dev_env: true)
      dev_mock.verify
    end

    # ensure production-like environments are disallowed
    staging_mock = Minitest::Mock.new
    staging_mock.expect :test?, false
    staging_mock.expect :pentest?, false

    Rails.stub :env, staging_mock do
      refute StudyCleanupTools.permit_environment?
      staging_mock.verify
    end
  end

  test 'should validate continuous integration' do
    mock_env('CI' => 'true') do
      assert StudyCleanupTools.is_continuous_integration?
    end

    mock_env('CI' => 'false') do
      refute StudyCleanupTools.is_continuous_integration?
    end

    mock_env('CI' => nil) do
      refute StudyCleanupTools.is_continuous_integration?
    end
  end

  test 'should match workspace creator for service account' do
    # use mock workspace JSON
    workspace = {
      workspace: {
        bucketName: "fc-#{SecureRandom.uuid}",
        createdBy: ApplicationController.firecloud_client.issuer,
        createdDate: DateTime.now.in_time_zone,
        lastModified: DateTime.now.in_time_zone,
        name: @basic_study.firecloud_workspace,
        namespace: @basic_study.firecloud_project,
      }
    }
    assert StudyCleanupTools.service_account_created_workspace?(workspace)

    not_owned_by_portal = {workspace: {createdBy: @user.email}}
    refute StudyCleanupTools.service_account_created_workspace?(not_owned_by_portal)
  end

  test 'should raise error on validation failure' do

    # positive tests - known goods should return nil as there is no declared return value
    # no arguments
    assert_nil StudyCleanupTools.raise_exception_unless_true('permit_environment?') { StudyCleanupTools.permit_environment? }

    # with arguments
    assert_nil StudyCleanupTools.raise_exception_unless_true('permit_billing_project?') { StudyCleanupTools.permit_billing_project? FireCloudClient::PORTAL_NAMESPACE }

    # negative test with no arguments - should throw RuntimeError
    begin
      mock = Minitest::Mock.new
      mock.expect :test?, false
      mock.expect :pentest?, false

      Rails.stub :env, mock do
        StudyCleanupTools.raise_exception_unless_true('permit_environment?') { StudyCleanupTools.permit_environment? }
      end
    rescue RuntimeError => error
      assert error.is_a?(RuntimeError)
      assert error.message.include?('permit_environment?'),
             "Did not find validation method signature for permit_environment? in message: #{error.message}"
      mock.verify
    end

    # negative test with arguments
    begin
      StudyCleanupTools.raise_exception_unless_true('permit_billing_project?') { StudyCleanupTools.permit_billing_project?('invalid-project') }
    rescue RuntimeError => error
      assert error.is_a?(RuntimeError)
      assert error.message.include?('permit_billing_project?'),
             "Did not find validation method signature for :permit_billing_project? in message: #{error.message}"
    end
  end

  test 'should validate confirmation prompt before deleting' do
    STDIN.stub :gets, 'Delete All' do
      assert StudyCleanupTools.confirm_delete_request?
    end

    STDIN.stub :gets, 'this should fail' do
      refute StudyCleanupTools.confirm_delete_request?
    end
  end
end
