require 'api_test_helper'
require 'user_tokens_helper'
require 'test_helper'
require 'includes_helper'

class PublicationsControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Directory Listing Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    @publication = @study.publications.create(url: 'https://www.pnas.org/doi/10.1073/pnas.2121720119',
                                              title: 'Cellular and transcriptional diversity over the course of human lactation ',
                                              journal: 'PNAS')
  end

  setup do
    sign_in_and_update @user
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    reset_user_tokens
  end

  test 'should get index' do
    execute_http_request(:get, api_v1_study_publications_path(@study))
    assert_response :success
    assert json.size >= 1, 'Did not find any publications'
  end

  test 'should get publication' do
    execute_http_request(:get, api_v1_study_publication_path(study_id: @study.id, id: @publication.id))
    assert_response :success
    # check all attributes against database
    @publication.attributes.each do |attribute, value|
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
  test 'should create then update then delete publication' do
    # create publication
    publication_attributes = {
        publication: {
            url: 'https://www.something.com',
            title: 'Something',
            journal: 'Foo'
        }
    }
    execute_http_request(:post, api_v1_study_publications_path(study_id: @study.id), request_payload: publication_attributes)
    assert_response :success
    assert json['title'] == publication_attributes[:publication][:title],
           "Did not set title correctly, expected #{publication_attributes[:publication][:title]} but found #{json['title']}"
    # update publication
    publication_id = json['_id']['$oid']
    url = 'https://www.everything.com'
    update_attributes = {
        publication: {
            url: url
        }
    }
    execute_http_request(:patch, api_v1_study_publication_path(study_id: @study.id, id: publication_id), request_payload: update_attributes)
    assert_response :success
    assert json['url'] == update_attributes[:publication][:url],
           "Did not set URL correctly, expected #{update_attributes[:publication][:url]} but found #{json['url']}"
    # delete publication
    execute_http_request(:delete, api_v1_study_publication_path(study_id: @study.id, id: publication_id))
    assert_response 204, "Did not successfully delete publication, expected response of 204 but found #{@response.response_code}"
  end
end
