require 'api_test_helper'
require 'user_tokens_helper'
require 'test_helper'
require 'includes_helper'
require 'detached_helper'

class StudiesControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @user_2 = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Test Studies API',
                               user: @user,
                               public: true,
                               test_array: @@studies_to_clean)
    @random_seed = SecureRandom.uuid
    @feature_flag = FeatureFlag.create(name: 'my_flag', default_value: false)
    sign_in_and_update @user
  end

  after(:all) do
    Study.where(name: /#{@random_seed}/, queued_for_deletion: false).map(&:destroy_and_remove_workspace)
    @feature_flag.destroy
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test 'should get index' do
    execute_http_request(:get, api_v1_studies_path)
    assert_response :success
    assert json.size >= 1, 'Did not find any studies'
  end

  test 'should get study' do
    mock_not_detached @study, :any_of do
      execute_http_request(:get, api_v1_study_path(@study))
      assert_response :success
      # check all attributes against database
      @study.attributes.each do |attribute, value|
        if attribute =~ /_id/ && attribute != 'bucket_id' # make sure we're not parsing string as JSON
          assert json[attribute] == JSON.parse(value.to_json), "Attribute mismatch: #{attribute} is incorrect, expected #{JSON.parse(value.to_json)} but found #{json[attribute.to_s]}"
        elsif attribute =~ /_at/
          assert_equal value.to_i, DateTime.parse(json[attribute]).to_i, "Attribute mismatch: #{attribute} is incorrect, expected #{value} but found #{DateTime.parse(json[attribute])}"
        else
          assert json[attribute] == value, "Attribute mismatch: #{attribute} is incorrect, expected #{value} but found #{json[attribute.to_s]}"
        end
      end

      # ensure we can get study by accession
      execute_http_request(:get, "/single_cell/api/v1/studies/#{@study.accession}")
      assert_response :success
      assert_equal @study.accession, json['accession']

      # ensure other users cannot access study
      sign_in_and_update(@user_2)
      execute_http_request(:get, api_v1_study_path(@study), user: @user_2)
      assert_response 403
    end
  end

  # create, update & delete tested together to use new object rather than main testing study
  test 'should create then update then delete study' do
    # create study
    study_attributes = {
        study: {
            name: "New Study #{@random_seed}"
        }
    }
    execute_http_request(:post, api_v1_studies_path, request_payload: study_attributes)
    assert_response :success
    assert json['name'] == study_attributes[:study][:name], "Did not set name correctly, expected #{study_attributes[:study][:name]} but found #{json['name']}"
    # update study, utilizing nested study_detail_attributes_full_description to ensure plain-text conversion works
    study_id = json['_id']['$oid']
    update_attributes = {
        study: {
            study_detail_attributes: {
                full_description: "<p>Test description #{SecureRandom.uuid}</p>"
            }
        }
    }
    execute_http_request(:patch, api_v1_study_path(id: study_id), request_payload: update_attributes)
    assert_response :success
    # since callback to update plain-text description no longer uses the same study reference, we must load it from
    # the database as the response will not have the updated description
    # see StudyDetail#set_study_description_text
    study = Study.find(study_id)
    plain_text_description = ActionController::Base.helpers.strip_tags update_attributes[:study][:study_detail_attributes][:full_description]
    assert study.description == plain_text_description, "Did not set description correctly, expected #{plain_text_description} but found #{json['description']}"
    # delete study, passing ?workspace=persist to skip FireCloud workspace deletion
    execute_http_request(:delete, api_v1_study_path(id: study_id))
    assert_response 204, "Did not successfully delete study, expected response of 204 but found #{@response.response_code}"
  end

  # get the study manifest for a study
  test 'should get study manifest' do
    mock_not_detached @study, :any_of do
      totat = @user.create_totat(30, manifest_api_v1_study_path(@study))
      get manifest_api_v1_study_path(@study), params: { auth_code: totat[:totat] }
      assert_response :success

      # should fail with bad totat
      totat = @user.create_totat(30, manifest_api_v1_study_path(@study))
      get manifest_api_v1_study_path(@study), params: { auth_code: 'haxxor' }
      assert_response 401

      # should fail if totat for a different purpose
      totat = @user.create_totat(30, "/api/v1/some/other/thing")
      get manifest_api_v1_study_path(@study), params: { auth_code: totat[:totat] }
      assert_response 401
    end
  end

  # test sync function by manually creating a new study using FireCloudClient methods, adding shares and files to the bucket,
  # then call sync_study API method
  test 'should create and then sync study' do
    # create study by calling FireCloud API manually
    study_name = "Sync Study #{@random_seed}"
    workspace_name = study_name.downcase.gsub(/[^a-zA-Z0-9]+/, '-').chomp('-')
    study_attributes = {
        study: {
            name: study_name,
            use_existing_workspace: true,
            firecloud_workspace: workspace_name,
            firecloud_project: FireCloudClient::PORTAL_NAMESPACE,
            user_id: @user.id
        }
    }
    puts 'creating workspace...'
    workspace = ApplicationController.firecloud_client.create_workspace(FireCloudClient::PORTAL_NAMESPACE, workspace_name)
    assert workspace_name = workspace['name'], "Did not set workspace name correctly, expected #{workspace_name} but found #{workspace['name']}"
    # create ACL
    puts 'creating ACL...'
    user_acl = ApplicationController.firecloud_client.create_workspace_acl(@user.email, 'WRITER', true, true)
    ApplicationController.firecloud_client.update_workspace_acl(FireCloudClient::PORTAL_NAMESPACE, workspace_name, user_acl)
    share_user = FactoryBot.create(:api_user)
    share_acl = ApplicationController.firecloud_client.create_workspace_acl(share_user.email, 'READER', true, false)
    ApplicationController.firecloud_client.update_workspace_acl(FireCloudClient::PORTAL_NAMESPACE, workspace_name, share_acl)
    # validate acl set
    workspace_acl = ApplicationController.firecloud_client.get_workspace_acl(FireCloudClient::PORTAL_NAMESPACE, workspace_name)
    assert workspace_acl['acl'][@user.email].present?, "Did not set study owner acl"
    assert workspace_acl['acl'][share_user.email].present?, "Did not set share acl"
    # manually add files to the bucket
    puts 'adding files to bucket...'
    fastq_filename = 'cell_1_R1_001.fastq.gz'
    metadata_filename = 'metadata_example.txt'
    fastq_path = Rails.root.join('test', 'test_data', fastq_filename).to_s
    metadata_path = Rails.root.join('test', 'test_data', metadata_filename).to_s
    ApplicationController.firecloud_client.execute_gcloud_method(:create_workspace_file, 0, workspace['bucketName'], fastq_path, fastq_filename)
    ApplicationController.firecloud_client.execute_gcloud_method(:create_workspace_file, 0, workspace['bucketName'], metadata_path, metadata_filename)
    assert ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, workspace['bucketName'], fastq_filename).present?,
           "Did not add fastq file to bucket"
    assert ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, workspace['bucketName'], metadata_filename).present?,
           "Did not add metadata file to bucket"
    # now create study entry
    puts 'adding study...'
    sync_study = Study.create!(study_attributes[:study])
    # call sync
    puts 'syncing study...'
    execute_http_request(:post, sync_api_v1_study_path(id: sync_study.id))
    assert json['study_shares'].detect {|share| share['email'] == share_user.email}.present?, "Did not create share for #{share_user.email}"
    assert json['study_files']['unsynced'].detect {|file| file['name'] == metadata_filename},
           "Did not find unsynced study file for #{metadata_filename}"
    assert json['directory_listings']['unsynced'].detect {|directory| directory['name'] == '/'}.present?,
           "Did not create directory_listing at root folder"
    assert json['directory_listings']['unsynced'].first['files'].detect {|file| file['name'] == fastq_filename}.present?,
           "Did not find #{fastq_filename} in directory listing files array"
    # clean up
    execute_http_request(:delete, api_v1_study_path(sync_study.id))
    assert_response 204, "Did not successfully delete sync study, expected response of 204 but found #{@response.response_code}"
  end

  test 'hidden files are identified by regex' do
    assert StudiesController::HIDDEN_FILE_REGEX.match('.foo').present?
    assert StudiesController::HIDDEN_FILE_REGEX.match('/whatever/.foo').present?
    assert StudiesController::HIDDEN_FILE_REGEX.match('/.config/config').present?

    assert StudiesController::HIDDEN_FILE_REGEX.match('/whatever/metadata.txt').nil?
    assert StudiesController::HIDDEN_FILE_REGEX.match('metadata.txt').nil?
  end

  test 'should enforce edit access restrictions on studies' do
    mock_not_detached @study, :any_of do
      # auth as other user
      sign_in_and_update(@user_2)
      update_attributes = {
        study: {
          public: false
        }
      }
      execute_http_request(:patch, api_v1_study_path(id: @study.id.to_s), request_payload: update_attributes, user: @user_2)
      assert_response 403
    end
  end

  test 'should get study file_info hash' do
    mock_not_detached @study, :any_of do
      sign_in_and_update(@user)
      execute_http_request(:get, file_info_api_v1_study_path(@study.accession, params: {include_options: true}), user: @user)
      assert_response :success
      %w[study files feature_flags menu_options].each do |key|
        assert json.keys.include?(key), "Did not find #{key} in json response: #{json.keys}"
      end
      # validate that feature flags are represented
      @user.set_flag_option(@feature_flag.name, true)
      @user.reload
      execute_http_request(:get, file_info_api_v1_study_path(@study.accession), user: @user)
      assert_response :success
      returned_flag = json.dig('feature_flags', @feature_flag.name)
      assert returned_flag
      # confirm study overrides user flags
      @study.set_flag_option(@feature_flag.name, false)
      @study.reload
      execute_http_request(:get, file_info_api_v1_study_path(@study.accession), user: @user)
      assert_response :success
      returned_flag = json.dig('feature_flags', @feature_flag.name)
      assert_not returned_flag
    end
  end
end
