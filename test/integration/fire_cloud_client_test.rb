require "test_helper"

##
#
# FireCloudClientTest - integration tests for FireCloudClient, validates client methods behave as expected & FireCloud API is functioning as normal
# Only covers Service Account level actions (cannot authenticate as user, so no workflow or billing unit tests)
#
# Also covers Google Cloud Storage integration (File IO into GCP buckets from workspaces)
#
##

class FireCloudClientTest < ActiveSupport::TestCase

  def setup
    @fire_cloud_client = Study.firecloud_client
    @test_email = 'singlecelltest@gmail.com'
    @random_test_seed = SecureRandom.uuid # use same random seed to differentiate between entire runs
  end

  ##
  #
  # TOKEN & STATUS TESTS
  #
  ##

  # refresh the FireCloud API access token
  # test only checks expiry date as we can't be sure that the access_token will actually refresh fast enough
  def test_refresh_access_token
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    expires_at = @fire_cloud_client.expires_at
    assert !@fire_cloud_client.access_token_expired?, 'Token should not be expired for new clients'
    @fire_cloud_client.refresh_access_token
    assert @fire_cloud_client.expires_at > expires_at, "Expiration date did not update, #{@fire_cloud_client.expires_at} is not greater than #{expires_at}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # refresh the GCS Driver
  # test only checks issue date as we can't be sure that the storage_access_token will actually refresh fast enough
  def test_refresh_google_storage_driver
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    issued_at = @fire_cloud_client.storage_issued_at
    new_storage = @fire_cloud_client.refresh_storage_driver
    assert new_storage.present?, 'New storage did not get instantiated'

    new_issued_at = new_storage.service.credentials.client.issued_at
    assert new_issued_at > issued_at, "Storage driver did not update, #{new_issued_at} is not greater than #{issued_at}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # assert status health check is returning true/false
  def test_firecloud_api_available
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # check that API is up
    api_available = @fire_cloud_client.api_available?
    assert [true, false].include?(api_available), 'Did not receive corret boolean response'

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # get the current FireCloud API status
  def test_firecloud_api_status
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

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

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  #
  # WORKSPACE TESTS
  #
  ##

  # test getting workspaces
  def test_workspaces
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    workspaces = @fire_cloud_client.workspaces(@fire_cloud_client.project)
    assert workspaces.any?, 'Did not find any workspaces'

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # main workspace test: create, get, set & update acls, delete
  def test_create_and_manage_workspace
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

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

    # delete workspace
    puts 'deleting workspace...'
    delete_message = @fire_cloud_client.delete_workspace(@fire_cloud_client.project, workspace_name)
    assert delete_message.has_key?('message'), 'Did not receive a delete confirmation'
    expected_confirmation = "Your Google bucket #{workspace['bucketName']} will be deleted within 24h."
    assert delete_message['message'].include?(expected_confirmation), "Did not receive correct confirmation, expected '#{expected_confirmation}' but found '#{delete_message['message']}'"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # test CRUDing workspace entities
  def test_create_and_manage_workspace_entities
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # set workspace name
    workspace_name = "#{self.method_name}-#{@random_test_seed}"

    # create workspace
    puts 'creating workspace...'
    workspace = @fire_cloud_client.create_workspace(@fire_cloud_client.project, workspace_name)
    assert workspace['name'] == workspace_name, "Name was not set correctly, expected '#{workspace_name}' but found '#{workspace['name']}'"

    # create default participant
    puts 'creating participant...'
    participant_upload = File.open(Rails.root.join('test', 'test_data', 'default_participant.tsv'))
    confirmation = @fire_cloud_client.import_workspace_entities_file(@fire_cloud_client.project, workspace_name, participant_upload)
    assert confirmation == 'participant', "Did not receive correct confirmation, expected 'participant' but found #{confirmation}"

    # create samples
    puts 'creating samples...'
    samples_upload = File.open(Rails.root.join('test', 'test_data', 'workspace_samples.tsv'))
    confirmation = @fire_cloud_client.import_workspace_entities_file(@fire_cloud_client.project, workspace_name, samples_upload)
    assert confirmation == 'sample', "Did not receive correct confirmation, expected 'sample' but found #{confirmation}"

    # get entity types
    puts 'getting entity types...'
    entity_types = @fire_cloud_client.get_workspace_entity_types(@fire_cloud_client.project, workspace_name)
    assert entity_types.keys.sort == %w(participant sample), "Did not find correct entity types, expected 'participant, sample' but found #{entity_types.keys}"

    # get single entity
    puts 'getting single entity...'
    default_participant = @fire_cloud_client.get_workspace_entity(@fire_cloud_client.project, workspace_name, 'participant', 'default_participant')
    assert default_participant.present?, 'Did not find default participant from direct query'

    # get all entities
    puts 'getting all entities...'
    workspace_entities = @fire_cloud_client.get_workspace_entities(@fire_cloud_client.project, workspace_name)
    assert workspace_entities.size == 6, "Did not find correct number of entities, expected 6 but found #{workspace_entities.size}"
    participant = workspace_entities.find {|entity| entity['entityType'] == 'participant'}
    assert participant.present?, 'Did not find default participant from workspace query'
    assert participant['name'] == 'default_participant', "Did not find correct name for participant, expected 'default_participant' but found #{participant['name']}"

    # get entities by type
    puts 'getting entities by type...'
    samples = @fire_cloud_client.get_workspace_entities_by_type(@fire_cloud_client.project, workspace_name, 'sample')
    assert samples.size == 5, "Did not find correct number of samples, expected 5 but found #{samples.size}"
    assert samples.first['entityType'] == 'sample', "Did not set entity type correctly, expected 'sample' but found '#{samples.first['entityType']}'"
    assert samples.first['name'] == 'sample_1', "Did not set entity type correctly, expected 'sample_1' but found '#{samples.first['entityName']}'"
    sample_attributes = samples.first['attributes']
    assert sample_attributes.size == 4, "Did not find correct number of sample attributes, expected 4 but found #{sample_attributes.size}"
    assert sample_attributes['participant'].present?, "Did not find participant attribute of sample"
    assert sample_attributes['participant']['entityName'] == 'default_participant', "Did not set correct association for participant, expected 'default_participant' but found #{sample_attributes['participant']['entityName']}"
    sample_attribute_names = sample_attributes.keys.delete_if {|key| key == 'participant'}
    assert sample_attribute_names.sort == %w(attribute_1	 attribute_2 attribute_3), "Did not find correct sample attributes, expected 'attribute_1, attribute_2, attribute_3' but found #{sample_attribute_names.join(', ')}"

    # get entities as tsv
    puts 'getting entities as tsv...'
    samples_tsv = @fire_cloud_client.get_workspace_entities_as_tsv(@fire_cloud_client.project, workspace_name, 'sample', sample_attribute_names)
    sample_tsv_vales = samples_tsv.split("\n").map {|line| line.split("\t")}
    assert sample_tsv_vales.size == 6, "TSV file did not have correct number of lines, expected 6 but found #{sample_tsv_vales.size}"
    assert sample_tsv_vales.last.size == sample_attribute_names.size + 1, "TSV row did not have correct number of entries, expected #{sample_attribute_names.size + 1} but found #{sample_tsv_vales.last.size}"

    # delete workspace entities
    puts 'deleting entities...'
    participant_map = @fire_cloud_client.create_entity_map(%w(default_participant), 'participant')
    sample_map = @fire_cloud_client.create_entity_map(%w(sample_1 sample_2 sample_3 sample_4 sample_5), 'sample')
    entity_map = participant_map + sample_map
    delete_confirmation = @fire_cloud_client.delete_workspace_entities(@fire_cloud_client.project, workspace_name, entity_map)
    assert delete_confirmation, 'Entities did not delete successfully'

    # delete workspace
    puts 'deleting workspace...'
    delete_message = @fire_cloud_client.delete_workspace(@fire_cloud_client.project, workspace_name)
    assert delete_message.has_key?('message'), 'Did not receive a delete confirmation'

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  #
  # WORKFLOW & CONFIGURATION TESTS (only a subset can be run as submissions require user authentication)
  #
  ##

  # get queue status
  def test_get_submission_queue_status
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    status = @fire_cloud_client.get_submission_queue_status
    assert status.any?, 'Did not receive queue status object'
    assert status['workflowCountsByStatus'].any?, 'Did not receive queue count status'

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # get available workflows
  def test_get_methods
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # get all available methods
    workflow_methods = @fire_cloud_client.get_methods(entityType: 'workflow')
    assert workflow_methods.any?, 'Did not find any workflow methods'

    # get a single method
    method_params = workflow_methods.sample
    method = @fire_cloud_client.get_method(method_params['namespace'], method_params['name'], method_params['snapshotId'])
    assert method.present?, "Did not retrieve requested method: '#{method_params['namespace']}/#{method_params['name']}/#{method_params['snapshotId']}'"

    # get a method payload
    method_payload = @fire_cloud_client.get_method(method_params['namespace'], method_params['name'], method_params['snapshotId'], true)
    assert method_payload.present?, "Did not retrieve requested method payload: '#{method_params['namespace']}/#{method_params['name']}/#{method_params['snapshotId']}'"
    assert method_payload.is_a?(String), "Method payload is wrong type, expected String but found #{method_payload.class}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # get method configurations
  def test_get_configurations
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # get all available configurations
    workflow_configurations = @fire_cloud_client.get_configurations
    assert workflow_configurations.any?, 'Did not find any method configurations'

    # get all configurations in 'single-cell-portal' namespace
    namespace = 'single-cell-portal'
    namespace_configs = @fire_cloud_client.get_configurations(namespace: namespace)
    assert namespace_configs.any?, "Did not find any method configurations in namespace: #{namespace}"

    # get a single configuration
    config_params = workflow_configurations.sample
    config = @fire_cloud_client.get_configuration(config_params['namespace'], config_params['name'], config_params['snapshotId'])
    assert config.present?, "Did not retrieve requested configuration: '#{config_params['namespace']}/#{config_params['name']}/#{config_params['snapshotId']}'"

    # get a configuration with method payload as JSON
    config_with_payload = @fire_cloud_client.get_configuration(config_params['namespace'], config_params['name'], config_params['snapshotId'], true)
    assert config_with_payload.present?, "Did not retrieve requested configuration with payload object: '#{config_params['namespace']}/#{config_params['name']}/#{config_params['snapshotId']}'"
    assert config_with_payload.has_key?('payloadObject'), 'Configuration did not have payloadObject'
    assert config_with_payload['payloadObject'].is_a?(Hash), "Did not return correct object type for payload, expected Hash but found #{config_with_payload['payloadObject'].class}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # create a method configuration template from a method
  def test_create_configuration_template
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    method = @fire_cloud_client.get_method('single-cell-portal', 'split-cluster', 1)
    assert method.present?, 'Did not retrieve a method to create a configuration template from'

    # create template
    configuration_template = @fire_cloud_client.create_configuration_template(method['namespace'], method['name'], method['snapshotId'])
    assert configuration_template.present?, 'Did not create a configuration template'
    template_method = configuration_template['methodRepoMethod']
    assert template_method['methodName'] == method['name'], "Configuration template method name is incorrect, expected '#{method['name']}' but found #{template_method['methodName']}"
    assert template_method['methodNamespace'] == method['namespace'], "Configuration template method name is incorrect, expected '#{method['namespace']}' but found #{template_method['methodNamespace']}"
    assert template_method['methodVersion'] == method['snapshotId'], "Configuration template method name is incorrect, expected '#{method['snapshotId']}' but found #{template_method['methodVersion']}"
    assert configuration_template['inputs'].any?, "Did not find any configuration inputs: #{configuration_template['inputs']}"
    assert configuration_template['outputs'].any?, "Did not find any configuration outputs: #{configuration_template['outputs']}"

    # get random method
    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # manage configurations in a workspace: copy, list all, get
  def test_manage_workspace_configurations
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # set workspace name
    workspace_name = "#{self.method_name}-#{@random_test_seed}"

    # create workspace
    puts 'creating workspace...'
    workspace = @fire_cloud_client.create_workspace(@fire_cloud_client.project, workspace_name)
    assert workspace.present?, 'Did not create workspace'

    puts 'loading configurations...'
    configurations = @fire_cloud_client.get_configurations
    assert configurations.any?, 'Did not load any configurations'

    # select configuration
    configuration = configurations.sample

    puts 'copying configuration to workspace...'
    begin
      copied_config = @fire_cloud_client.copy_configuration_to_workspace(@fire_cloud_client.project, workspace_name, configuration['namespace'], configuration['name'], configuration['snapshotId'], workspace['namespace'], configuration['name'])
      assert copied_config['methodConfiguration']['name'] == configuration['name'], "Copied configuration name is incorrect, expected '#{configuration['name']}' but found '#{copied_config['methodConfiguration']['name']}'"
      assert copied_config['methodConfiguration']['namespace'] == workspace['namespace'], "Copied configuration name is incorrect, expected '#{workspace['namespace']}' but found '#{copied_config['methodConfiguration']['namespace']}'"
    rescue => e
      @fire_cloud_client.delete_workspace(@fire_cloud_client.project, workspace_name)
      skip "Skipping test due to error from methods repo (this is not a regression but a known issue with some methods missing configurations): #{e.message}"
    end

    puts 'getting workspace configurations...'
    workspace_configs = @fire_cloud_client.get_workspace_configurations(@fire_cloud_client.project, workspace_name)
    assert workspace_configs.any?, 'Did not find any workspace configurations'

    puts 'getting single workspace configuration...'
    ws_config = workspace_configs.first
    single_configuration = @fire_cloud_client.get_workspace_configuration(@fire_cloud_client.project, workspace_name, ws_config['namespace'], ws_config['name'])
    assert single_configuration.any?, "Did not load workspace configuration: #{ws_config['name']}"
    assert single_configuration.has_key?('inputs'), "Single workspace configuration '#{single_configuration['name']}' has no inputs"
    assert single_configuration.has_key?('outputs'), "Single workspace configuration '#{single_configuration['name']}' has no outputs"

    puts 'updating workspace configuration'
    updated_input = single_configuration['inputs'].keys.first
    updated_value = 'this is the update'
    single_configuration['inputs'][updated_input] = updated_value
    update_request = @fire_cloud_client.update_workspace_configuration(@fire_cloud_client.project, workspace_name, single_configuration['namespace'], single_configuration['name'], single_configuration)
    assert update_request.present?, "Request did not go through, response is nil: #{update_request}"
    updated_config = @fire_cloud_client.get_workspace_configuration(@fire_cloud_client.project, workspace_name, ws_config['namespace'], ws_config['name'])
    assert updated_config['inputs'][updated_input] == updated_value, "did not update configuration input, expected '#{updated_value}' but found '#{updated_config['inputs'][updated_input]}'"

    puts 'overwriting workspace configuration'
    new_value = 'this is a new update'
    single_configuration['inputs'][updated_input] = new_value
    overwrite_request = @fire_cloud_client.overwrite_workspace_configuration(@fire_cloud_client.project, workspace_name, ws_config['namespace'], ws_config['name'], single_configuration)
    assert overwrite_request.present?, "Overwrite did not go through, response is nil: #{overwrite_request}"
    overwritten_config = @fire_cloud_client.get_workspace_configuration(@fire_cloud_client.project, workspace_name, ws_config['namespace'], ws_config['name'])
    assert overwritten_config['inputs'][updated_input] == new_value, "did not overwrite configuration input, expected '#{new_value}' but found '#{overwritten_config['inputs'][updated_input]}'"

    # delete workspace
    puts 'deleting workspace...'
    delete_message = @fire_cloud_client.delete_workspace(@fire_cloud_client.project, workspace_name)
    assert delete_message.has_key?('message'), 'Did not receive a delete confirmation'

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  #
  # USER GROUP TESTS
  #
  ##

  # main groups test - CRUD group & members
  def test_create_and_mange_user_groups
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # set group name
    group_name = "test-group-#{@random_test_seed}"
    puts 'creating group...'
    group = @fire_cloud_client.create_user_group(group_name)
    assert group.present?, 'Did not create user group'

    puts 'adding user to group...'
    user_role = FireCloudClient::USER_GROUP_ROLES.sample
    user_added = @fire_cloud_client.add_user_to_group(group_name, user_role, @test_email)
    assert user_added, 'Did not add user to group'

    puts 'getting user groups...'
    groups = @fire_cloud_client.get_user_groups
    assert groups.any?, 'Did not find any user groups'

    puts 'getting user group...'
    group = @fire_cloud_client.get_user_group(group_name)
    assert group.present?, "Did not retrieve user group: #{group_name}"
    email_key = user_role == 'admin' ? 'adminsEmails' : 'membersEmails'
    assert group[email_key].include?(@test_email), "Test group did not have #{@test_email} as member of #{email_key}: #{group[email_key]}"

    puts 'delete user from group...'
    delete_user = @fire_cloud_client.delete_user_from_group(group_name, user_role, @test_email)
    assert delete_user, 'Did not delete user from group'

    puts 'confirming user delete...'
    updated_group = @fire_cloud_client.get_user_group(group_name)
    assert !updated_group[email_key].include?(@test_email), "Test group did still has #{@test_email} as member of #{email_key}: #{updated_group[email_key]}"

    puts 'deleting user group...'
    delete_group = @fire_cloud_client.delete_user_group(group_name)
    assert delete_group, 'Did not delete user group'

    puts 'confirming user group delete...'
    updated_groups = @fire_cloud_client.get_user_groups
    group_names = updated_groups.map {|g| g['groupName']}
    assert !group_names.include?(group_name), "Test group '#{group_name}' was not deleted: #{group_names.join(', ')}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  #
  # BILLING TESTS (does not test create billing projects as we cannot delete them yet)
  #
  ##

  # get available billing projects
  def test_get_billing_projects
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # get all projects
    projects = @fire_cloud_client.get_billing_projects
    assert projects.any?, 'Did not find any billing projects'

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # update a billing project's member list
  def test_update_billing_project_members
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # get all projects
    puts 'selecting project...'
    projects = @fire_cloud_client.get_billing_projects
    assert projects.any?, 'Did not find any billing projects'

    # select a project (only valid projects, not in the compute blacklist)
    project_name = projects.select {|p| p['creationStatus'] == 'Ready' && !FireCloudClient::COMPUTE_BLACKLIST.include?(p['projectName'])}.sample['projectName']
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
    updated_users = @fire_cloud_client.get_billing_project_members(project_name)
    emails = updated_users.map {|user| user['email']}
    assert !emails.include?(@test_email), "Did not successfully remove #{@test_email} from list of billing project members: #{emails.join(', ')}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  #
  # GCS TESTS
  #
  ##

  # get a workspace's GCS bucket
  def test_get_workspace_bucket
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # set workspace name
    workspace_name = "#{self.method_name}-#{@random_test_seed}"

    # create workspace
    puts 'creating workspace...'
    workspace = @fire_cloud_client.create_workspace(@fire_cloud_client.project, workspace_name)
    assert workspace.present?, 'Did not create workspace'

    # get workspace bucket
    bucket = @fire_cloud_client.execute_gcloud_method(:get_workspace_bucket, 0, workspace['bucketName'])
    assert bucket.name == workspace['bucketName'], "Bucket does not have correct name, expected '#{workspace['bucketName']}' but found '#{bucket.name}'"

    # delete workspace
    puts 'deleting workspace...'
    delete_message = @fire_cloud_client.delete_workspace(@fire_cloud_client.project, workspace_name)
    assert delete_message.has_key?('message'), 'Did not receive a delete confirmation'

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # main File IO test for buckets: create, copy, download, delete
  def test_get_workspace_files
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # set workspace name
    workspace_name = "#{self.method_name}-#{@random_test_seed}"

    # create workspace
    puts 'creating workspace...'
    workspace = @fire_cloud_client.create_workspace(@fire_cloud_client.project, workspace_name)
    assert workspace.present?, 'Did not create workspace'

    puts 'uploading files...'
    # puts "SSL_CERT_FILE = #{ENV['SSL_CERT_FILE']}"
    # puts "SSL_CERT_DIR = #{ENV['SSL_CERT_DIR']}"

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
    # load study for place to download files to
    @study = Study.first
    downloaded_file = @fire_cloud_client.execute_gcloud_method(:download_workspace_file, 0, workspace['bucketName'], file.name, @study.data_store_path)
    assert downloaded_file.present?, 'Did not download local copy of file'
    assert downloaded_file.to_path == File.join(@study.data_store_path, file.name), "Did not download #{file.name} to #{@study.data_store_path}, downloaded file is at #{downloaded_file.to_path}"
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

    # delete workspace
    puts 'deleting workspace...'
    delete_message = @fire_cloud_client.delete_workspace(@fire_cloud_client.project, workspace_name)
    assert delete_message.has_key?('message'), 'Did not receive a delete confirmation'

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end
end
