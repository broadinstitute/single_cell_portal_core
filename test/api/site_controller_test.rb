require 'api_test_helper'

class SiteControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include Requests::JsonHelpers
  include Requests::HttpHelpers

  setup do
    @user = User.first
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
                                                                           :provider => 'google_oauth2',
                                                                           :uid => '123545',
                                                                           :email => 'testing.user@gmail.com'
                                                                       })
    sign_in @user
    @random_seed = File.open(Rails.root.join('.random_seed')).read.strip
  end

  test 'should get all studies' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    execute_http_request(:get, api_v1_site_studies_path)
    assert_response :success
    assert json.size >= 3, "Did not find correct number of studies, expected 3 or more but found #{json.size}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should get one study' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    @study = Study.find_by(name: "API Test Study #{@random_seed}")
    execute_http_request(:get, api_v1_site_study_view_path(accession: @study.accession))
    assert_response :success
    assert json['study_files'].size == 4, "Did not find correct number of files, expected 4 but found #{json['study_files'].size}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should get all analyses' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    execute_http_request(:get, api_v1_site_analyses_path)
    assert_response :success
    assert json.size == 1, "Did not find correct number of analyses, expected 1 but found #{json.size}"
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should get one analysis' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    @analysis_configuration = AnalysisConfiguration.first
    execute_http_request(:get, api_v1_site_get_analysis_path(namespace: @analysis_configuration.namespace,
                                                             name: @analysis_configuration.name,
                                                             snapshot: @analysis_configuration.snapshot))
    assert_response :success
    assert json['name'] == @analysis_configuration.name,
           "Did not load correct analysis name, expected '#{@analysis_configuration.name}' but found '#{json['name']}'"
    assert json['description'] == @analysis_configuration.description,
           "Description did not match; expected '#{@analysis_configuration.description}' but found '#{json['description']}'"
    assert json['required_inputs'] == @analysis_configuration.required_inputs(true),
           "Required inputs do not match; expected '#{@analysis_configuration.required_inputs(true)}' but found #{json['required_inputs']}"
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should respond 410 on detached study' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # manually set detached to validate 410 status
    @study = Study.find_by(name: "API Test Study #{@random_seed}")
    @study.update(detached: true)
    file = @study.study_files.first

    execute_http_request(:get, api_v1_site_study_download_data_path(accession: @study.accession, filename: file.upload_file_name))
    assert_response 410,
                    "Did not provide correct response code when downloading file from detached study, expected 401 but found #{response.code}"

    # reset status so downstream tests don't break
    @study.update(detached: false)
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should download file' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    @study = Study.find_by(name: "API Test Study #{@random_seed}")
    file = @study.study_files.first

    execute_http_request(:get, api_v1_site_study_download_data_path(accession: @study.accession, filename: file.upload_file_name))
    assert_response 302, "Did not correctly redirect to file: #{response.code}"

    # since this is an external redirect, we cannot call follow_redirect! but instead have to get the location header
    signed_url = response.headers['Location']
    assert signed_url.include?(file.upload_file_name), "Redirect url does not point at requested file"

    # now assert 401 if user isn't signed in
    # we can mimic the sign-out by unsetting the user object so that no Authorization: Bearer token is passed with the request
    @user = nil
    execute_http_request(:get, api_v1_site_study_download_data_path(accession: @study.accession, filename: file.upload_file_name))
    assert_response 401, "Did not correctly respond 401 if user is not signed in: #{response.code}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should get stream options for file' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    @study = Study.find_by(name: "API Test Study #{@random_seed}")
    file = @study.study_files.first

    execute_http_request(:get, api_v1_site_study_stream_data_path(accession: @study.accession, filename: file.upload_file_name))
    assert_response :success
    assert_equal file.upload_file_name, json['filename'],
                 "Incorrect file was returned; #{file.upload_file_name} != #{json['filename']}"
    assert json['url'].include?(file.upload_file_name),
                                "Url does not contain correct file: #{file.upload_file_name} is not in #{json['url']}"

    # since this is a 'public' study, the access token in the read-only service account token
    public_token = ApplicationController.read_only_firecloud_client.valid_access_token['access_token']
    assert_equal public_token, json['access_token']

    # assert 401 if no user is signed in
    @user = nil
    execute_http_request(:get, api_v1_site_study_stream_data_path(accession: @study.accession, filename: file.upload_file_name))
    assert_response 401, "Did not correctly respond 401 if user is not signed in: #{response.code}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'external sequence data should return correct download link' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    @study = Study.find_by(name: "API Test Study #{@random_seed}")
    external_sequence_file = @study.study_files.by_type('Fastq').first
    execute_http_request(:get, api_v1_site_study_view_path(accession: @study.accession))
    assert_response :success
    external_entry = json['study_files'].detect {|file| file['name'] == external_sequence_file.name}
    assert_equal external_sequence_file.human_fastq_url, external_entry['download_url'],
                 "Did not return correct download url for external fastq; #{external_entry['download_url']} != #{external_sequence_file.human_fastq_url}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end
end
