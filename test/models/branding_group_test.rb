require 'test_helper'

class BrandingGroupTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @admin = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @branding_group = FactoryBot.create(:branding_group, user_list: [@user])
  end

  after(:all) do
    BrandingGroup.destroy_all
  end

  test 'should return list of approved facets for branding groups' do
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
  end

  test 'should check edit permissions' do
    assert @branding_group.can_edit?(@user)
    assert @branding_group.can_edit?(@admin)
    other_user = FactoryBot.create(:user, test_array: @@users_to_clean)
    assert_not @branding_group.can_edit?(other_user)
  end

  test 'should check destroy permissions' do
    assert @branding_group.can_destroy?(@admin)
    assert_not @branding_group.can_destroy?(@user)
  end
end
