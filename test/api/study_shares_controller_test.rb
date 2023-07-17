require 'api_test_helper'
require 'user_tokens_helper'
require 'test_helper'
require 'includes_helper'
require 'detached_helper'

class StudySharesControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @other_user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'StudyFileBundle Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    @study_share = StudyShare.create!(email: @other_user.email, permission: 'Reviewer', study: @study)
  end

  setup do
    sign_in_and_update @user
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    reset_user_tokens
  end

  test 'should get index' do
    mock_not_detached @study, :find_by do
      execute_http_request(:get, api_v1_study_study_shares_path(@study))
      assert_response :success
      assert json.size >= 1, 'Did not find any study_shares'
    end
  end

  test 'should get study share' do
    mock_not_detached @study, :find_by do
      execute_http_request(:get, api_v1_study_study_share_path(study_id: @study.id, id: @study_share.id))
      assert_response :success
      # check all attributes against database
      @study_share.attributes.each do |attribute, value|
        case attribute
        when /_id/
          assert json[attribute] == JSON.parse(value.to_json),
                 "Attribute mismatch: #{attribute} is incorrect, expected #{JSON.parse(value.to_json)} " \
                      "but found #{json[attribute.to_s]}"
        when /_at/
          # ignore timestamps as formatting & drift on milliseconds can cause comparison errors
          next
        else
          assert json[attribute] == value,
                 "Attribute mismatch: #{attribute} is incorrect, expected #{value} " \
                      "but found #{json[attribute.to_s]}"
        end
      end
    end
  end

  # create, update & delete tested together to use new object to avoid delete/update running before create
  test 'should create then update then delete study share' do
    mock_not_detached @study, :find_by do
      # create study share
      study_share_attributes = {
        study_share: {
          email: 'some.person@gmail.com',
          permission: 'Reviewer'
        }
      }
      execute_http_request(
        :post, api_v1_study_study_shares_path(study_id: @study.id), request_payload: study_share_attributes
      )
      assert_response :success
      assert json['email'] == study_share_attributes[:study_share][:email],
             "Did not set email correctly, expected #{study_share_attributes[:study_share][:email]} " \
                  "but found #{json['email']}"
      # update study share
      study_share_id = json['_id']['$oid']
      update_attributes = {
        study_share: {
          deliver_emails: false
        }
      }
      execute_http_request(:patch,
                           api_v1_study_study_share_path(study_id: @study.id, id: study_share_id),
                           request_payload: update_attributes)
      assert_response :success
      assert json['deliver_emails'] == update_attributes[:study_share][:deliver_emails],
             "Did not set deliver_emails correctly, expected " \
                  "#{update_attributes[:study_share][:deliver_emails]} but found #{json['deliver_emails']}"
      # delete study share
      execute_http_request(:delete, api_v1_study_study_share_path(study_id: @study.id, id: study_share_id))
      assert_response 204, "Did not successfully delete study file, expected response of 204 " \
                           "but found #{@response.response_code}"
    end
  end
end
