require 'api_test_helper'

class ApiBaseControllerTest < ActionDispatch::IntegrationTest
  include Requests::JsonHelpers
  include Requests::HttpHelpers

  setup do
    @configured_version = AdminConfiguration.get_ingest_docker_image_attributes[:tag]
  end

  test 'should allow all requests without user agent header' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    get api_v1_site_studies_path
    assert_response :success, "Did not get correct response; 200 != #{response.code}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should allow valid scp user agent header values' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    ua_header = {"User-Agent" => "scp-ingest-pipeline/#{@configured_version}"}
    get api_v1_site_studies_path, headers: ua_header
    assert_response :success, "Did not get correct response; 200 != #{response.code}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should reject invalid scp user agent header values' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    maj_version = @configured_version[0].to_i
    version_parts = @configured_version.split('.')
    version_parts[0] = maj_version - 1
    bad_version = version_parts.join('.')
    bad_header = {"User-Agent" => "scp-ingest-pipeline/#{bad_version}"}
    get api_v1_site_studies_path, headers: bad_header
    assert_response :bad_request, "Did not respond correctly; 400 != #{response.code}"
    assert json['error'].include?('--upgrade'), "Did not find --upgrade message in #{json['error']}"
    assert json['error'].include?(bad_version), "Did not find request version tag of #{bad_version} in #{json['error']}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should match ingest image tags exactly when overridden' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # override image
    image_name = 'gcr.io/broad-singlecellportal-staging/scp-ingest-pipeline-development:ddee8f5'
    config = AdminConfiguration.create!(config_type: AdminConfiguration::INGEST_DOCKER_NAME, value_type: 'String',
                                        value: image_name)
    current_tag = AdminConfiguration.get_ingest_docker_image_attributes[:tag]

    # validate exact matching of version tags
    good_header = {"User-Agent" => "scp-ingest-pipeline/#{current_tag}"}
    get api_v1_site_studies_path, headers: good_header
    assert_response :success, "Did not get correct response; 200 != #{response.code}"

    bad_header = {"User-Agent" => "scp-ingest-pipeline/this-does-not-match"}
    get api_v1_site_studies_path, headers: bad_header
    assert_response :bad_request, "Did not respond correctly; 400 != #{response.code}"

    # clean up
    config.destroy

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end
end
