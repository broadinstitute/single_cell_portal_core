require 'test_helper'

##
#
# FireCloudClientTest - integration tests for FireCloudClient, validates client methods behave as expected & FireCloud API is functioning as normal
# Only covers Service Account level actions (cannot authenticate as user, so no workflow or billing unit tests)
#
# Also covers Google Cloud Storage integration (File IO into GCP buckets from workspaces)
#
##

class FireCloudClientTest < ActiveSupport::TestCase

  before(:all) do
    @smoke_test = ENV['ORCH_SMOKE_TEST'] == 'true'
    if @smoke_test
      api_root = 'https://firecloud-orchestration.dsde-staging.broadinstitute.org'
      puts "Running smoke test against Terra orchestration API at #{api_root}"
      @fire_cloud_client = FireCloudClient.new(api_root:)
    else
      @fire_cloud_client = ApplicationController.firecloud_client
    end

    @test_email = 'singlecelltest@gmail.com'
    @random_test_seed = SecureRandom.uuid # use same random seed to differentiate between entire runs
    @resource_error_msg = 'Resource representation is only available with these types' # for error handling

    # seed one workspace to prevent test_workspaces from failing due to order of operations corner case
    workspace_name = "workspace-#{@random_test_seed}"
    Rails.logger.info "seeding #{workspace_name} for testing"
    @fire_cloud_client.create_workspace(@fire_cloud_client.project, workspace_name)
  end

  # given ongoing issues with workspace deletion throwing spurious errors, do cleanup at end and ignore errors
  after(:all) do
    test_workspaces = @fire_cloud_client.workspaces(FireCloudClient::PORTAL_NAMESPACE).keep_if do |workspace|
      workspace['workspace']['name'].match(@random_test_seed)
    end
    puts "running cleanup of #{test_workspaces.count} test workspaces"
    test_workspaces.each do |workspace|
      workspace_info = workspace['workspace']
      begin
        ws_project = workspace_info['namespace']
        ws_name = workspace_info['name']
        puts "deleting #{ws_project}/#{ws_name}"
        @fire_cloud_client.delete_workspace(ws_project, ws_name)
      rescue RuntimeError => e
        # ignore errors in cleanup as they're likely due to the 'Resource representation is only available' issue
        puts "Error removing workspace: #{e.message}" unless e.message.match(@resource_error_msg)
      end
    end
  end

  ##
  #
  # TOKEN & STATUS TESTS
  #
  ##

  # refresh the FireCloud API access token
  # test only checks expiry date as we can't be sure that the access_token will actually refresh fast enough
  def test_refresh_access_token
    expires_at = @fire_cloud_client.expires_at
    assert !@fire_cloud_client.access_token_expired?, 'Token should not be expired for new clients'
    @fire_cloud_client.refresh_access_token!
    assert @fire_cloud_client.expires_at > expires_at, "Expiration date did not update, #{@fire_cloud_client.expires_at} is not greater than #{expires_at}"
  end

  # refresh the GCS Driver
  # test only checks issue date as we can't be sure that the storage_access_token will actually refresh fast enough
  def test_refresh_google_storage_driver
    instance_id = @fire_cloud_client.storage.service.__id__
    new_storage = @fire_cloud_client.refresh_storage_driver
    assert new_storage.present?, 'New storage did not get instantiated'

    new_instance_id = new_storage.service.__id__
    assert_not_equal instance_id, new_instance_id
  end

  # assert status health check is returning true/false
  def test_firecloud_api_available
    # check that API is up
    api_available = @fire_cloud_client.api_available?
    assert [true, false].include?(api_available), 'Did not receive corret boolean response'
  end

  # get the current FireCloud API status
  def test_firecloud_api_status
    status = @fire_cloud_client.api_status
    assert status.is_a?(Hash), "Did not get expected status Hash object; found #{status.class.name}"
    assert status['ok'].present?, 'Did not find root status message'
    assert status['systems'].present?, 'Did not find system statuses'
    # look for presence of systems that SCP depends on
    services = [FireCloudClient::RAWLS_SERVICE, FireCloudClient::SAM_SERVICE, FireCloudClient::AGORA_SERVICE,
                FireCloudClient::THURLOE_SERVICE, FireCloudClient::BUCKETS_SERVICE]
    services.each do |service|
      assert status['systems'][service].present?, "Did not find required service: #{service}"
      assert [true, false].include?(status['systems'][service]['ok']), "Did not find expected 'ok' message of true/false; found: #{status['systems'][service]['ok']}"
    end
  end

  # test header overrides
  def test_override_default_headers
    headers = %w[Accept Content-Type]
    default_headers = @fire_cloud_client.get_default_headers
    override_headers = @fire_cloud_client.get_default_headers(content_type: 'text/plain')
    headers.each do |header|
      assert_equal 'application/json', default_headers[header]
      assert_equal 'text/plain', override_headers[header]
    end
  end

  ##
  #
  # WORKSPACE TESTS
  #
  ##

  # test getting workspaces
  def test_workspaces
    workspaces = @fire_cloud_client.workspaces(@fire_cloud_client.project)
    assert workspaces.any?, 'Did not find any workspaces'
  end

  # main workspace test: create, get, set & update acls, delete
  def test_create_and_manage_workspace
    # set workspace name
    workspace_name = "#{self.method_name}-#{@random_test_seed}"

    # create workspace
    puts 'creating workspace...'
    workspace = @fire_cloud_client.create_workspace(@fire_cloud_client.project, workspace_name)
    assert workspace['name'] == workspace_name, "Name was not set correctly, expected '#{workspace_name}' but found '#{workspace['name']}'"

    # get workspace
    puts 'retrieving workspace...'
    retrieved_workspace = @fire_cloud_client.get_workspace(@fire_cloud_client.project, workspace_name)
    assert retrieved_workspace.present?, "Did not find requested workspace: #{workspace_name}"

    # set ACL
    puts 'setting workspace acl...'
    acl = @fire_cloud_client.create_workspace_acl(@test_email, 'OWNER')
    updated_workspace = @fire_cloud_client.update_workspace_acl(@fire_cloud_client.project, workspace_name, acl)
    assert updated_workspace['usersUpdated'].size == 1, 'Did not update a user in workspace'

    # retrieve new ACL
    puts 'retrieving workspace acl...'
    ws_acl = @fire_cloud_client.get_workspace_acl(@fire_cloud_client.project, workspace_name)
    assert ws_acl['acl'].keys.include?(@test_email), "Workspace ACL does not contain #{@test_email}"
    assert ws_acl['acl'][@test_email]['accessLevel'] == 'OWNER', "Workspace ACL does not list #{@test_email} as owner"

    # set workspace attribute
    puts 'setting workspace attribute...'
    new_attribute = {
        'random_attribute' => @random_test_seed
    }
    updated_ws_attributes = @fire_cloud_client.set_workspace_attributes(@fire_cloud_client.project, workspace_name, new_attribute)
    assert updated_ws_attributes['attributes'] == new_attribute, "Did not properly set new attribute to workspace, expected '#{new_attribute}' but found '#{updated_ws_attributes['attributes']}'"
  end

  def test_delete_workspace
    workspace_name = "#{self.method_name}-#{@random_test_seed}"

    # create workspace
    puts 'creating workspace...'
    workspace = @fire_cloud_client.create_workspace(@fire_cloud_client.project, workspace_name)
    assert workspace['name'] == workspace_name, "Name was not set correctly, expected '#{workspace_name}' but found '#{workspace['name']}'"

    # delete workspace
    begin
      puts 'deleting workspace...'
      @fire_cloud_client.delete_workspace(@fire_cloud_client.project, workspace_name)
    rescue RuntimeError => e
      raise e unless e.message.include?(@resource_error_msg)
    end
  end

  def test_check_bucket_read_access
    skip if @smoke_test
    workspace_name = "workspace-#{@random_test_seed}"
    # since the timing is arbitrary, we can't be sure that issuing a request will then result in success downstream
    # instead, validate that access either is granted (true), or that the FastPass has been requested (false)
    read_access = @fire_cloud_client.check_bucket_read_access(@fire_cloud_client.project, workspace_name)
    assert_includes [true, false], read_access
  end

  ##
  #
  # BILLING TESTS (does not test create billing projects as we cannot delete them yet)
  #
  ##

  # get available billing projects
  def test_get_billing_projects
    # get all projects
    projects = @fire_cloud_client.get_billing_projects
    assert projects.any?, 'Did not find any billing projects'
  end

  # update a billing project's member list
  def test_update_billing_project_members
    skip if @smoke_test
    # get all projects
    puts 'selecting project...'
    projects = @fire_cloud_client.get_billing_projects
    assert projects.any?, 'Did not find any billing projects'

    # select a project (only valid projects, not in the compute denylist)
    project_name = projects.select do |p|
      p['status'] == 'Ready' &&
        !FireCloudClient::COMPUTE_DENYLIST.include?(p['projectName']) &&
        p['roles'].include?('Owner')
    end.sample['projectName']
    assert project_name.present?, 'Did not select a billing project'

    # get users
    puts 'getting project users...'
    users = @fire_cloud_client.get_billing_project_members(project_name)
    assert users.any?, 'Did not retrieve billing project users'

    # add user to project
    puts 'adding user to project...'
    user_role = FireCloudClient::BILLING_PROJECT_ROLES.sample
    user_added = @fire_cloud_client.add_user_to_billing_project(project_name, user_role, @test_email)
    assert user_added == 'OK', "Did not add user to project: #{user_added}"

    # get updated list of users
    puts 'confirming user add...'
    updated_users = @fire_cloud_client.get_billing_project_members(project_name)
    emails = updated_users.map {|user| user['email']}
    assert emails.include?(@test_email), "Did not successfully add #{@test_email} to list of billing project members: #{emails.join(', ')}"
    added_user = updated_users.find {|user| user['email'] == @test_email}
    assert added_user['role'].downcase == user_role, "Did not set user role for #{@test_email} correctly; expected '#{user_role}' but found '#{added_user['role'].downcase}'"

    # remove user
    puts 'deleting user from billing project...'
    user_deleted = @fire_cloud_client.delete_user_from_billing_project(project_name, user_role, @test_email)
    assert user_deleted == 'OK', "Did not delete user from project: #{user_deleted}"

    puts 'confirming user delete...'
    final_users = @fire_cloud_client.get_billing_project_members(project_name)
    final_emails = final_users.map {|user| user['email']}

    # handle possible upstream latency with user list propagating back to Google
    if emails.sort == final_emails.sort
      puts 'user list has not updated, retrying in 1 second'
      sleep 1
      final_users = @fire_cloud_client.get_billing_project_members(project_name)
      final_emails = final_users.map {|user| user['email']}
    end

    assert !final_emails.include?(@test_email), "Did not successfully remove #{@test_email} from list of billing project members: #{emails.join(', ')}"
  end

  def test_should_retry_error_codes
    ApiHelpers::RETRY_STATUS_CODES.each do |code|
      assert @fire_cloud_client.should_retry?(code)
    end
  end

  ##
  #
  # GCS TESTS
  #
  ##

  # get a workspace's GCS bucket
  def test_get_workspace_bucket
    # set workspace name
    workspace_name = "#{self.method_name}-#{@random_test_seed}"

    # create workspace
    puts 'creating workspace...'
    workspace = @fire_cloud_client.create_workspace(@fire_cloud_client.project, workspace_name)
    assert workspace.present?, 'Did not create workspace'

    # get workspace bucket
    bucket = @fire_cloud_client.execute_gcloud_method(:get_workspace_bucket, 0, workspace['bucketName'])
    assert bucket.name == workspace['bucketName'], "Bucket does not have correct name, expected '#{workspace['bucketName']}' but found '#{bucket.name}'"
  end

  # main File IO test for buckets: create, copy, download, delete
  def test_get_workspace_files
    # set workspace name
    workspace_name = "#{self.method_name}-#{@random_test_seed}"

    # create workspace
    puts 'creating workspace...'
    workspace = @fire_cloud_client.create_workspace(@fire_cloud_client.project, workspace_name)
    assert workspace.present?, 'Did not create workspace'

    puts 'uploading files...'
    # upload files
    participant_upload = File.open(Rails.root.join('test', 'test_data', 'default_participant.tsv'))
    participant_filename = File.basename(participant_upload)
    uploaded_participant = @fire_cloud_client.execute_gcloud_method(:create_workspace_file, 0, workspace['bucketName'], participant_upload.to_path, participant_filename)
    assert uploaded_participant.present?, 'Did not upload participant file'
    assert uploaded_participant.name == participant_filename, "Name not set correctly on uploaded participant file, expected '#{participant_filename}' but found '#{uploaded_participant.name}'"

    samples_upload = File.open(Rails.root.join('test', 'test_data', 'workspace_samples.tsv'))
    samples_filename = File.basename(samples_upload)
    uploaded_samples = @fire_cloud_client.execute_gcloud_method(:create_workspace_file, 0, workspace['bucketName'], samples_upload.to_path, samples_filename)
    assert uploaded_samples.present?, 'Did not upload samples file'
    assert uploaded_samples.name == samples_filename, "Name not set correctly on uploaded participant file, expected '#{samples_filename}' but found '#{uploaded_samples.name}'"

    # get remote files
    puts 'getting files...'
    bucket_files = @fire_cloud_client.execute_gcloud_method(:get_workspace_files, 0, workspace['bucketName'])
    assert bucket_files.size == 2, "Did not find correct number of files, expected 2 but found #{bucket_files.size}"

    # get single remote file
    puts 'getting single file...'
    bucket_file = bucket_files.sample
    file_exists = @fire_cloud_client.workspace_file_exists?(workspace['bucketName'], bucket_file.name)
    assert file_exists, "Did not locate bucket file '#{bucket_file.name}'"
    file = @fire_cloud_client.execute_gcloud_method(:get_workspace_file, 0, workspace['bucketName'], bucket_file.name)
    assert file.present?, "Did not retrieve bucket file '#{bucket_file.name}'"
    assert file.generation == bucket_file.generation, "Generation tag is incorrect on retrieved file, expected '#{bucket_file.generation}' but found '#{file.generation}'"

    # copy a file to new destination
    copy_destination = "copy_destination_path/new_#{file.name}"
    copied_file = @fire_cloud_client.execute_gcloud_method(:copy_workspace_file, 0, workspace['bucketName'], file.name, copy_destination)
    assert copied_file.present?, 'Did not copy file'
    assert copied_file.name == copy_destination, "Did not copy file to correct destination, expected '#{copy_destination}' but found #{copied_file.name}"

    # download remote file to local
    puts 'downloading file...'
    download_path = Rails.root.join('tmp')
    downloaded_file = @fire_cloud_client.execute_gcloud_method(:download_workspace_file, 0, workspace['bucketName'], file.name, download_path)
    assert downloaded_file.present?, 'Did not download local copy of file'
    assert downloaded_file.to_path == File.join(download_path, file.name), "Did not download #{file.name} to #{download_path}, downloaded file is at #{downloaded_file.to_path}"
    # clean up download
    File.delete(downloaded_file.to_path)

    # generate a signed URL for a file
    puts 'getting signed URL for file...'
    seconds_to_expire = 15
    signed_url = @fire_cloud_client.execute_gcloud_method(:generate_signed_url, 0, workspace['bucketName'], participant_filename, expires: seconds_to_expire)
    signed_url_response = RestClient.get signed_url
    assert signed_url_response.code == 200, "Did not receive correct response code on signed_url, expected 200 but found #{signed_url_response.code}"
    participant_contents = participant_upload.read
    assert participant_contents == signed_url_response.body, "Response body contents are incorrect, expected '#{participant_contents}' but found '#{signed_url_response.body}'"

    # check timeout
    sleep(seconds_to_expire)
    begin
      RestClient.get signed_url
    rescue RestClient::BadRequest => timeout
      expected_message = '400 Bad Request'
      expected_error_class = RestClient::BadRequest
      assert timeout.message == expected_message, "Did not receive correct error message, expected '#{expected_message}' but found '#{timeout.message}'"
      assert timeout.class == expected_error_class, "Did not receive correct error class, expected '#{expected_error_class}' but found '#{timeout.class}'"
    end

    # generate a media URL for a file
    puts 'getting API URL for file...'
    api_url = @fire_cloud_client.execute_gcloud_method(:generate_api_url, 0, workspace['bucketName'], participant_filename)
    assert api_url.start_with?("https://www.googleapis.com/storage"), "Did not receive correctly formatted api_url, expected to start with 'https://www.googleapis.com/storage' but found #{api_url}"

    puts 'reading file into memory...'
    remote_file = @fire_cloud_client.execute_gcloud_method(:read_workspace_file, 0, workspace['bucketName'], participant_filename)
    remote_contents = remote_file.read
    assert remote_contents == participant_contents,
           "Did not correctly read remote file into memory, contents did not match\n## remote ##\n#{remote_contents}\n## local ##\n#{participant_contents}"

    # close upload files
    participant_upload.close
    samples_upload.close

    # get files at a specific location
    puts 'getting files at location...'
    location = 'copy_destination_path'
    files_at_location = @fire_cloud_client.execute_gcloud_method(:get_workspace_directory_files, 0, workspace['bucketName'], location)
    assert files_at_location.size == 1, "Did not find correct number of files, expected 1 but found #{files_at_location.size}"

    # delete remote file
    puts 'deleting file...'
    num_files = @fire_cloud_client.execute_gcloud_method(:get_workspace_files, 0, workspace['bucketName']).size
    delete_confirmation = @fire_cloud_client.execute_gcloud_method(:delete_workspace_file, 0, workspace['bucketName'], file.name)
    assert delete_confirmation, 'File did not delete, confirmation did not return true'
    current_num_files = @fire_cloud_client.execute_gcloud_method(:get_workspace_files, 0, workspace['bucketName']).size
    assert current_num_files == num_files - 1, "Number of files is incorrect, expected #{num_files - 1} but found #{current_num_files}"
  end

  # this test simulates errors and ensures that retries are only executed when the status code mandates
  def test_should_handle_retry_by_status_code
    error = proc { raise Google::Cloud::Error, 'something bad happened' }
    @fire_cloud_client.stub :get_workspace_bucket, error do
      # should only retry once
      forbidden_mock = Minitest::Mock.new
      status = 403
      forbidden_mock.expect :status_code, status
      forbidden_mock.expect :nil?, false
      3.times do
        forbidden_mock.expect :==, false, [Integer] # will check against 502..504
      end
      @fire_cloud_client.stub :extract_status_code, forbidden_mock do
        assert_raise RuntimeError do
          @fire_cloud_client.execute_gcloud_method(:get_workspace_file, 0, 'foo', 'bar.txt')
          forbidden_mock.verify
        end
      end
      # test with 502 should cause retry cascade
      status = 502
      bad_gateway_mock = Minitest::Mock.new
      6.times do # 6 is for 5 total requests and then 6th iteration that terminates retry loop
        bad_gateway_mock.expect :status_code, status
        bad_gateway_mock.expect :nil?, false
        bad_gateway_mock.expect :==, true, [status]
      end
      @fire_cloud_client.stub :extract_status_code, bad_gateway_mock do
        assert_raise RuntimeError do
          @fire_cloud_client.execute_gcloud_method(:get_workspace_file, 0, 'foo', 'bar.txt')
          bad_gateway_mock.verify
        end
      end
    end
  end
end
