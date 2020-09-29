require "test_helper"

class SyntheticBrandingGroupPopulatorTest < ActiveSupport::TestCase

  test 'should populate synthetic branding groups' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    branding_group_count = BrandingGroup.count

    # populate all synthetic groups
    SyntheticBrandingGroupPopulator.populate_all
    updated_count = BrandingGroup.count
    expected_count = branding_group_count + 2
    assert_equal expected_count, updated_count,
                 "Did not create correct number of groups; expected #{expected_count} but found #{updated_count}"

    configurations = SyntheticBrandingGroupPopulator.load_all_config_files
    configurations.each do |configuration|
      group_name = configuration.dig('branding_group', 'name')
      group = BrandingGroup.find_by(name: group_name)
      assert group.present?, "Could not find branding group called #{group_name}"
      configuration['branding_group'].each do |name, value|
        loaded_value = group.send(name)
        assert_equal value, loaded_value,
                     "Value for #{name} is incorrect; expected #{value} but found #{loaded_value}"
      end
    end

    # delete all synthetic groups
    SyntheticBrandingGroupPopulator.remove_all
    final_count = BrandingGroup.count
    assert_equal branding_group_count, final_count,
                 "Did not remove synthetic branding groups; expected #{branding_group_count} but found #{final_count}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end
end
