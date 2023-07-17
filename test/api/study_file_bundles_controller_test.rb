require 'api_test_helper'
require 'user_tokens_helper'
require 'test_helper'
require 'includes_helper'
require 'detached_helper'

class StudyFileBundlesControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'StudyFileBundle Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    @study_file_bundle = StudyFileBundle.create!(
      bundle_type: 'BAM',
      original_file_list: [
        { 'name' => 'sample_1.bam', 'file_type' => 'BAM' },
        { 'name' => 'sample_1.bam.bai', 'file_type' => 'BAM Index' }
      ],
      study: @study
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
    mock_not_detached @study, :find_by do
      execute_http_request(:get, api_v1_study_study_file_bundles_path(@study))
      assert_response :success
      assert json.size >= 1, 'Did not find any study_file_bundles'
    end
  end

  test 'should get study file bundle' do
    mock_not_detached @study, :find_by do
      execute_http_request(:get, api_v1_study_study_file_bundle_path(study_id: @study.id, id: @study_file_bundle.id))
      assert_response :success
      # check all attributes against database
      @study_file_bundle.attributes.each do |attribute, value|
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
  end

  # create & delete tested together to use new object to avoid delete running before create
  test 'should create then delete study file bundle' do
    mock_not_detached @study, :find_by do
      # create study file bundle
      study_file_bundle_attributes = {
        'study_file_bundle' => {
          'original_file_list' => [
            { 'name' => 'matrix.mtx', 'file_type' => 'MM Coordinate Matrix' },
            { 'name' => 'genes.tsv', 'file_type' => '10X Genes File' },
            { 'name' => 'barcodes.tsv', 'file_type' => '10X Barcodes File' }
          ]
        }
      }
      execute_http_request(:post, api_v1_study_study_file_bundles_path(study_id: @study.id), request_payload: study_file_bundle_attributes)
      assert_response :success
      assert json['original_file_list'] == study_file_bundle_attributes['study_file_bundle']['original_file_list'],
             "Did not set name correctly, expected #{study_file_bundle_attributes['study_file_bundle']['original_file_list']} but found #{json['original_file_list']}"
      # delete study file bundle
      study_file_bundle_id = json['_id']['$oid']
      execute_http_request(:delete, api_v1_study_study_file_bundle_path(study_id: @study.id, id: study_file_bundle_id))
      assert_response 204, "Did not successfully delete study file bundle, expected response of 204 but found #{@response.response_code}"
    end
  end
end
