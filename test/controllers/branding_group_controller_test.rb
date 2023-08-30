require 'api_test_helper'
require 'test_helper'
require 'integration_test_helper'
require 'includes_helper'

class BrandingGroupControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @admin = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    TosAcceptance.create(email: @admin.email)
    TosAcceptance.create(email: @user.email)
    @collection = FactoryBot.create(:branding_group, user_list: [@user])
  end

  after(:all) do
    BrandingGroup.destroy_all
  end

  test 'should show public collection list' do
    get collection_list_navigate_path
    assert_response :success
    assert_select "li##{@collection.name_as_id}", 1
  end

  test 'should show collections private to curators' do
    new_collection = FactoryBot.create(:branding_group, user_list: [@user], public: false)
    sign_in @user
    get collection_list_navigate_path
    assert_response :success
    assert_select "li##{new_collection.name_as_id}", 1
  end

  test 'should enforce authentication for editing collections' do
    get edit_branding_group_path(@collection)
    assert_redirected_to new_user_session_path
    other_user = FactoryBot.create(:user, test_array: @@users_to_clean)
    TosAcceptance.create(email: other_user.email)
    sign_in other_user
    get edit_branding_group_path(@collection)
    assert_redirected_to collection_list_navigate_path
    sign_out other_user
    sign_in @user
    get edit_branding_group_path(@collection)
    assert_response :success
    assert_select 'form.branding-group-form', 1
  end

  test 'should update collection' do
    sign_in @user
    updated_tag = 'This is a new tagline'
    collection_params = {
      branding_group: {
        tag_line: updated_tag
      },
      curator_emails: '',
      study_accessions: ''
    }
    patch branding_group_path(@collection), params: collection_params
    assert_redirected_to branding_group_path(@collection)
    @collection.reload
    assert_equal updated_tag, @collection.tag_line
    # test mass assignment of studies/curators
    new_user = FactoryBot.create(:user, test_array: @@users_to_clean)
    studies = []
    5.times do
      studies << FactoryBot.create(:detached_study,
                                   name_prefix: 'Collection Mass Assignment',
                                   user: @user,
                                   test_array: @@studies_to_clean)
    end
    accessions = studies.shuffle.take(3).map(&:accession)
    curator_params = {
      curator_emails: [@user.email, new_user.email].join(','),
      study_accessions: accessions.join(','),
      branding_group: {
        name: @collection.name # need at least one parameter to avoid ActionController::ParameterMissing
      }
    }
    patch branding_group_path(@collection), params: curator_params
    assert_redirected_to branding_group_path(@collection)
    @collection.reload
    assert @collection.can_edit?(@user)
    assert @collection.can_edit?(new_user)
    assert_equal 3, @collection.study_list.size
    assert_equal accessions.sort, @collection.study_list.sort
    accessions = [studies.first.accession]
    # test sanitizer logic by using blank space and extra commas
    curator_params = {
      curator_emails: " #{@user.email}  , ,",
      study_accessions: "      #{studies.first.accession},,, ",
      branding_group: {
        name: @collection.name
      }
    }
    patch branding_group_path(@collection), params: curator_params
    assert_redirected_to branding_group_path(@collection)
    @collection.reload
    assert @collection.can_edit?(@user)
    assert_not @collection.can_edit?(new_user)
    assert_equal accessions, @collection.study_list
  end

  test 'should enforce admin credentials for creating/deleting collections' do
    sign_in @user
    collection_name = 'My New Collection'
    collection_params = {
      branding_group: {
        name: collection_name,
        user_ids: [@user.id],
        font_family: 'Helvetica Neue, sans-serif',
        background_color: '#FFFFFF',
        public: true
      },
      curator_emails: @user.email,
      study_accessions: ''
    }
    post branding_groups_path, params: collection_params
    assert_redirected_to site_path
    assert_not BrandingGroup.where(name: collection_name).exists?
    sign_out @user
    sign_in @admin
    post branding_groups_path, params: collection_params
    new_collection = BrandingGroup.find_by(name: collection_name)
    assert new_collection.present?
    assert_redirected_to branding_group_path(new_collection)
    sign_out @admin
    sign_in @user
    delete branding_group_path(new_collection)
    assert_redirected_to site_path
    assert BrandingGroup.where(name: collection_name).exists?
    sign_out @user
    sign_in @admin
    delete branding_group_path(new_collection)
    assert_redirected_to branding_groups_path
    assert_not BrandingGroup.where(name: collection_name).exists?
  end
end
