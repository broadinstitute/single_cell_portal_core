require 'api_test_helper'

class StudiesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include Requests::JsonHelpers
  include Requests::HttpHelpers

  setup do
    @random_seed = File.open(Rails.root.join('.random_seed')).read.strip
    @user = User.first
    @study = Study.find_by(name: "API Test Study #{@random_seed}")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
                                                                           :provider => 'google_oauth2',
                                                                           :uid => '123545',
                                                                           :email => 'testing.user@gmail.com'
                                                                       })
    sign_in @user
  end

  test 'should get index' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    execute_http_request(:get, api_v1_studies_path)
    assert_response :success
    assert json.size >= 1, 'Did not find any studies'
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should get study' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    execute_http_request(:get, api_v1_study_path(@study))
    assert_response :success
    # check all attributes against database
    @study.attributes.each do |attribute, value|
      if attribute =~ /_id/ && attribute != 'bucket_id' # make sure we're not parsing string as JSON
        assert json[attribute] == JSON.parse(value.to_json), "Attribute mismatch: #{attribute} is incorrect, expected #{JSON.parse(value.to_json)} but found #{json[attribute.to_s]}"
      elsif attribute =~ /_at/
        assert DateTime.parse(json[attribute]) == value, "Attribute mismatch: #{attribute} is incorrect, expected #{value} but found #{DateTime.parse(json[attribute])}"
      else
        assert json[attribute] == value, "Attribute mismatch: #{attribute} is incorrect, expected #{value} but found #{json[attribute.to_s]}"
      end
    end
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # create, update & delete tested together to use new object rather than main testing study
  test 'should create then update then delete study' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    # create study
    study_attributes = {
        study: {
            name: "New Study #{SecureRandom.uuid}"
        }
    }
    execute_http_request(:post, api_v1_studies_path, study_attributes)
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
    execute_http_request(:patch, api_v1_study_path(id: study_id), update_attributes)
    assert_response :success
    plain_text_description = ActionController::Base.helpers.strip_tags update_attributes[:study][:study_detail_attributes][:full_description]
    assert json['description'] == plain_text_description, "Did not set description correctly, expected #{plain_text_description} but found #{json['description']}"
    # delete study, passing ?workspace=persist to skip FireCloud workspace deletion
    execute_http_request(:delete, api_v1_study_path(id: study_id))
    assert_response 204, "Did not successfully delete study, expected response of 204 but found #{@response.response_code}"
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # test sync function by manually creating a new study using FireCloudClient methods, adding shares and files to the bucket,
  # then call sync_study API method
  test 'should create and then sync study' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    # create study by calling FireCloud API manually
    study_name = "Sync Study #{SecureRandom.uuid}"
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
    workspace = Study.firecloud_client.create_workspace(FireCloudClient::PORTAL_NAMESPACE, workspace_name)
    assert workspace_name = workspace['name'], "Did not set workspace name correctly, expected #{workspace_name} but found #{workspace['name']}"
    # create ACL
    puts 'creating ACL...'
    user_acl = Study.firecloud_client.create_workspace_acl(@user.email, 'WRITER', true, true)
    Study.firecloud_client.update_workspace_acl(FireCloudClient::PORTAL_NAMESPACE, workspace_name, user_acl)
    share_user = User.find_by(email: 'testing.user.2@gmail.com')
    share_acl = Study.firecloud_client.create_workspace_acl(share_user.email, 'READER', true, false)
    Study.firecloud_client.update_workspace_acl(FireCloudClient::PORTAL_NAMESPACE, workspace_name, share_acl)
    # validate acl set
    workspace_acl = Study.firecloud_client.get_workspace_acl(FireCloudClient::PORTAL_NAMESPACE, workspace_name)
    assert workspace_acl['acl'][@user.email].present?, "Did not set study owner acl"
    assert workspace_acl['acl'][share_user.email].present?, "Did not set share acl"
    # manually add files to the bucket
    puts 'adding files to bucket...'
    fastq_filename = 'cell_1_R1_001.fastq.gz'
    metadata_filename = 'metadata_example.txt'
    fastq_path = Rails.root.join('test', 'test_data', fastq_filename).to_s
    metadata_path = Rails.root.join('test', 'test_data', metadata_filename).to_s
    Study.firecloud_client.execute_gcloud_method(:create_workspace_file, 0, workspace['bucketName'], fastq_path, fastq_filename)
    Study.firecloud_client.execute_gcloud_method(:create_workspace_file, 0, workspace['bucketName'], metadata_path, metadata_filename)
    assert Study.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, workspace['bucketName'], fastq_filename).present?,
           "Did not add fastq file to bucket"
    assert Study.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, workspace['bucketName'], metadata_filename).present?,
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
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'hidden files are identified by regex' do
    assert StudiesController::HIDDEN_FILE_REGEX.match('.foo').present?
    assert StudiesController::HIDDEN_FILE_REGEX.match('/whatever/.foo').present?
    assert StudiesController::HIDDEN_FILE_REGEX.match('/.config/config').present?

    assert StudiesController::HIDDEN_FILE_REGEX.match('/whatever/metadata.txt').nil?
    assert StudiesController::HIDDEN_FILE_REGEX.match('metadata.txt').nil?
  end
end
