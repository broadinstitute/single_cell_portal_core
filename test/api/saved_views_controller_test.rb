require 'api_test_helper'
require 'user_tokens_helper'
require 'test_helper'
require 'includes_helper'

class SavedViewsControllerTest < ActionDispatch::IntegrationTest
  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'SavedView Controller Test',
                               user: @user,
                               test_array: @@studies_to_clean)
    @saved_view = FactoryBot.create(:saved_view,
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

  test 'should get saved view' do
    execute_http_request(:get, api_v1_saved_view_path(id: @saved_view.id))
    assert_response :success
    # check all attributes against database
    @saved_view.attributes.each do |attribute, value|
      case attribute
      when /_id/
        assert json[attribute] == JSON.parse(value.to_json),
               "Attribute mismatch: #{attribute} is incorrect, expected #{JSON.parse(value.to_json)} but found " \
                    "#{json[attribute.to_s]}"

      when /_at/
        next
      else
        assert json[attribute] == value,
               "Attribute mismatch: #{attribute} is incorrect, expected #{value} but found #{json[attribute.to_s]}"
      end
    end
  end

  test 'should create then update then delete saved view' do
    # create saved_view
    saved_view_attributes = {
      saved_view: {
        path: '/single_cell/study/SCP1234',
        name: 'My Saved View'
      }
    }
    execute_http_request(:post, api_v1_saved_views_path, request_payload: saved_view_attributes)
    assert_response :success
    assert json['name'] == saved_view_attributes[:saved_view][:name],
           "Did not set name correctly, expected #{saved_view_attributes[:saved_view][:name]} but found #{json['name']}"
    # update saved_view
    saved_view_id = json['_id']['$oid']
    description = 'This is the description'
    update_attributes = { saved_view: { description: } }
    execute_http_request(:patch, api_v1_saved_view_path(id: saved_view_id), request_payload: update_attributes)
    assert_response :success
    assert json['description'] == update_attributes[:saved_view][:description],
           "Did not set description correctly, expected #{update_attributes[:saved_view][:description]} " \
                "but found #{json['description']}"
    # delete saved_view
    execute_http_request(:delete, api_v1_saved_view_path(id: saved_view_id))
    assert_response 204, "Did not delete saved_view, expected response of 204 but found #{@response.response_code}"
  end
end
