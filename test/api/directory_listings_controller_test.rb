require 'api_test_helper'
require 'user_helper'
require 'test_helper'
require 'includes_helper'

class DirectoryListingsControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Directory Listing Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    @directory_listing = DirectoryListing.create!(
      name: 'csvs', file_type: 'csv', files: [{ 'name' => 'foo.csv', 'size' => 100, 'generation' => '12345' }],
      sync_status: true, study: @study
    )
  end

  setup do
    sign_in_and_update @user
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    reset_user_tokens
  end

  test 'should get index' do
    execute_http_request(:get, api_v1_study_directory_listings_path(@study))
    assert_response :success
    assert json.size >= 1, 'Did not find any directory_listings'
  end

  test 'should get directory listing' do
    execute_http_request(:get, api_v1_study_directory_listing_path(study_id: @study.id, id: @directory_listing.id))
    assert_response :success
    # check all attributes against database
    @directory_listing.attributes.each do |attribute, value|
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
  test 'should create then update then delete directory listing' do
    # create directory listing
    files = []
    1.upto(5) do |i|
      files << {
          "name" => "exp_#{i}.gct",
          "size" => i * 100,
          "generation" => "#{SecureRandom.random_number.to_s.split('.').last[0..15]}"
      }
    end
    directory_listing_attributes = {
        "directory_listing" => {
            "name" => 'some_dir',
            "file_type" => 'gct',
            "files" =>  files
        }
    }
    execute_http_request(:post,
                         api_v1_study_directory_listings_path(study_id: @study.id),
                         request_payload: directory_listing_attributes)
    assert_response :success
    assert json['name'] == directory_listing_attributes["directory_listing"]["name"], "Did not set name correctly, expected #{directory_listing_attributes["directory_listing"]["name"]} but found #{json['name']}"
    # update directory listing
    directory_listing_id = json['_id']['$oid']
    new_file = {
        "name" => 'exp_6.gct',
        "size" => 600,
        "generation" => "#{SecureRandom.random_number.to_s.split('.').last[0..15]}"
    }
    files << new_file
    update_attributes = {
        "directory_listing" => {
            "sync_status" => false,
            "files" => files
        }
    }
    execute_http_request(:patch, api_v1_study_directory_listing_path(study_id: @study.id, id: directory_listing_id), request_payload: update_attributes)
    assert_response :success
    assert json['sync_status'] == update_attributes["directory_listing"]["sync_status"], "Did not set sync_status correctly, expected #{update_attributes["directory_listing"]["sync_status"]} but found #{json['sync_status']}"
    assert json['files'] == update_attributes["directory_listing"]["files"], "Did not set files correctly, expected #{update_attributes["directory_listing"]["files"]} but found #{json['files']}"
    # delete directory listing
    execute_http_request(:delete, api_v1_study_directory_listing_path(study_id: @study.id, id: directory_listing_id))
    assert_response 204, "Did not successfully delete study file, expected response of 204 but found #{@response.response_code}"
  end
end
