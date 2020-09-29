require "test_helper"

class AdminConfigurationTest < ActiveSupport::TestCase
  def setup
    @client = FireCloudClient.new
  end

  # since the migration SetSaGroupOwnerOnWorkspaces will have already run, we are ensuring that calling
  # AdminConfiguration.find_or_create_ws_user_group! retrieves the user group rather than creating a new one
  test 'should create or retrieve service account workspace owner group' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    first_sa_group = AdminConfiguration.find_or_create_ws_user_group!
    assert_not_nil first_sa_group, 'Did not create/retrieve service account workspace owner group'

    groups = @client.get_user_groups
    found_group = groups.detect {|group| group['groupName'] == FireCloudClient::WS_OWNER_GROUP_NAME}
    assert_not_nil found_group, 'Did not find service account workspace owner group in groups'

    second_sa_group = AdminConfiguration.find_or_create_ws_user_group!
    assert_equal first_sa_group, second_sa_group,
                 "Service account workspace owner groups not the same: #{first_sa_group} != #{second_sa_group}"

    second_groups = @client.get_user_groups
    first_group_names = groups.map {|group| group['groupName']}.sort
    second_group_names = second_groups.map {|group| group['groupName']}.sort
    assert_equal first_group_names, second_group_names,
                 "Groups are not the same: #{first_group_names} != #{second_group_names}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # test getting the default configured ingest docker image, and overriding via admin_configuration
  test 'should retrieve ingest docker image tag from config' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # default configured image
    default_image = Rails.application.config.ingest_docker_image
    config_image = AdminConfiguration.get_ingest_docker_image
    assert_equal default_image, config_image,
                 "Ingest image names do not match; #{default_image} != #{config_image}"

    # override image
    image_name = 'gcr.io/broad-singlecellportal-staging/scp-ingest-pipeline:1.0.0-rc1'
    new_config_image = AdminConfiguration.create!(config_type: AdminConfiguration::INGEST_DOCKER_NAME,
                                                  value_type: 'String',
                                                  value: image_name)
    current_image = AdminConfiguration.get_ingest_docker_image
    assert_equal image_name, current_image,
                 "Updated ingest image names do not match; #{image_name} != #{current_image}"

    # revert to default
    new_config_image.destroy
    reverted_image = AdminConfiguration.get_ingest_docker_image
    assert_equal default_image, reverted_image,
                 "Reverted ingest image names do not match; #{default_image} != #{reverted_image}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should revert ingest image to default' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    default_image = Rails.application.config.ingest_docker_image

    # add new image config
    image_name = 'gcr.io/broad-singlecellportal-staging/scp-ingest-pipeline:1.0.0-rc1'
    new_config_image = AdminConfiguration.create!(config_type: AdminConfiguration::INGEST_DOCKER_NAME,
                                                  value_type: 'String',
                                                  value: image_name)
    assert new_config_image.present?, "Ingest image config did not save"

    # run cleanup job
    AdminConfiguration.revert_ingest_docker_image
    config = AdminConfiguration.get_ingest_docker_image_config
    assert config.nil?, "Ingest docker image configuration still present"
    current_image = AdminConfiguration.get_ingest_docker_image
    assert_equal default_image, current_image,
                 "Reverted ingest image names do not match; #{default_image} != #{current_image}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should extract docker image attributes from image name string' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    image_attributes = AdminConfiguration.get_ingest_docker_image_attributes
    expected_keys = [:registry, :project, :image_name, :tag]
    image_attributes.each do |attribute, value|
      assert expected_keys.include?(attribute), "Unexpected attribute name found: #{attribute}; not in #{expected_keys}"
      assert value.present?, "Did not retrieve a value for #{attribute}: #{value}"
    end

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end
end
