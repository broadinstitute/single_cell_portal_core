require 'api_test_helper'
require 'user_helper'
require 'test_helper'
require 'includes_helper'

class ExternalResourcesControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Directory Listing Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    @external_resource = @study.external_resources.create(url: 'https://singlecell.broadinstitute.org', title: 'SCP',
                                                          description: 'Link to Single Cell Portal')
  end

  setup do
    sign_in_and_update @user
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    reset_user_tokens
  end

  test 'should get index' do
    execute_http_request(:get, api_v1_study_external_resources_path(@study))
    assert_response :success
    assert json.size >= 1, 'Did not find any external_resources'
  end

  test 'should get external resource' do
    execute_http_request(:get, api_v1_study_external_resource_path(study_id: @study.id, id: @external_resource.id))
    assert_response :success
    # check all attributes against database
    @external_resource.attributes.each do |attribute, value|
      if attribute =~ /_id/
        assert json[attribute] == JSON.parse(value.to_json), "Attribute mismatch: #{attribute} is incorrect, expected #{JSON.parse(value.to_json)} but found #{json[attribute.to_s]}"
      elsif attribute =~ /_at/
        # ignore timestamps as formatting & drift on milliseconds can cause comparison errors
        next
      else
        assert json[attribute] == value, "Attribute mismatch: #{attribute} is incorrect, expected #{value} but found #{json[attribute.to_s]}"
      end
    end
  end

  # create, update & delete tested together to use new object to avoid delete/update running before create
  test 'should create then update then delete external resource' do
    # create external_resource
    external_resource_attributes = {
        external_resource: {
            url: 'https://www.something.com',
            title: 'Something'
        }
    }
    execute_http_request(:post, api_v1_study_external_resources_path(study_id: @study.id), request_payload: external_resource_attributes)
    assert_response :success
    assert json['title'] == external_resource_attributes[:external_resource][:title],
           "Did not set title correctly, expected #{external_resource_attributes[:external_resource][:title]} but found #{json['title']}"
    # update external_resource
    external_resource_id = json['_id']['$oid']
    description = 'This is the description'
    update_attributes = {
        external_resource: {
            description: description
        }
    }
    execute_http_request(:patch, api_v1_study_external_resource_path(study_id: @study.id, id: external_resource_id), request_payload: update_attributes)
    assert_response :success
    assert json['description'] == update_attributes[:external_resource][:description],
           "Did not set description correctly, expected #{update_attributes[:external_resource][:description]} but found #{json['description']}"
    # delete external_resource
    execute_http_request(:delete, api_v1_study_external_resource_path(study_id: @study.id, id: external_resource_id))
    assert_response 204, "Did not successfully delete external_resource, expected response of 204 but found #{@response.response_code}"
  end
end
