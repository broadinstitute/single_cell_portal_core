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
end
