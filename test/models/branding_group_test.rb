require "test_helper"

class BrandingGroupTest < ActiveSupport::TestCase

  def setup
    @branding_group = BrandingGroup.first
  end

  test 'should return list of approved facets for branding groups' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # test that default returns all visible facets
    visible_facets = SearchFacet.visible.pluck(:identifier).sort
    branding_group_facets = @branding_group.facets.pluck(:identifier).sort
    assert_equal visible_facets, branding_group_facets,
                 "Did not return all visible facets w/o facet list; #{visible_facets} != #{branding_group_facets}"

    # test that facet_list returns correct facets
    facet_list = visible_facets.take(2)
    @branding_group.update(facet_list: facet_list)
    branding_facet_list = @branding_group.facets.pluck(:identifier).sort
    assert_equal facet_list, branding_facet_list,
                 "Did not return filtered lists of facets; #{facet_list} != #{branding_facet_list}"

    # clean up
    @branding_group.update(facet_list: [])

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end
end
