require 'api_test_helper'
require 'user_tokens_helper'
require 'test_helper'
require 'includes_helper'

class BookmarksControllerTest < ActionDispatch::IntegrationTest
  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Bookmark Controller Test',
                               user: @user,
                               test_array: @@studies_to_clean)
    @bookmark = FactoryBot.create(:bookmark,
                                  user: @user,
                                  name: 'My Favorite Study',
                                  path: "/study/#{@study.accession}")
  end

  setup do
    sign_in_and_update @user
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    reset_user_tokens
  end

  test 'should create, update then delete bookmark' do
    # create bookmark
    bookmark_attributes = {
      bookmark: {
        path: '/single_cell/study/SCP1234',
        name: 'My Saved View'
      }
    }
    execute_http_request(:post, api_v1_bookmarks_path, request_payload: bookmark_attributes)
    assert_response :success
    assert json['name'] == bookmark_attributes[:bookmark][:name],
           "Did not set name correctly, expected #{bookmark_attributes[:bookmark][:name]} but found #{json['name']}"
    # update bookmark
    bookmark_id = json['_id']
    description = 'This is the description'
    update_attributes = { bookmark: { description: } }
    execute_http_request(:patch, api_v1_bookmark_path(id: bookmark_id), request_payload: update_attributes)
    assert_response :success
    assert json['description'] == update_attributes[:bookmark][:description],
           "Did not set description correctly, expected #{update_attributes[:bookmark][:description]} " \
                "but found #{json['description']}"
    # delete bookmark
    execute_http_request(:delete, api_v1_bookmark_path(id: bookmark_id))
    assert_response 204, "Did not delete bookmark, expected response of 204 but found #{@response.response_code}"
  end
end
