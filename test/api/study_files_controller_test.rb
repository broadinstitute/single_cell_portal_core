require 'api_test_helper'
require 'user_tokens_helper'
require 'test_helper'
require 'includes_helper'

class StudyFilesControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @other_user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:study,
                               name_prefix: 'StudyFile Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    @study_file = FactoryBot.create(:cluster_file,
                               name: 'clusterA.txt',
                               study: @study)
  end

  setup do
    sign_in_and_update @user
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    reset_user_tokens
  end

  test 'should get index' do
    execute_http_request(:get, api_v1_study_study_files_path(@study))
    assert_response :success
    assert json.size >= 1, 'Did not find any study_files'
  end

  test 'should get study file' do
    execute_http_request(:get, api_v1_study_study_file_path(study_id: @study.id, id: @study_file.id))
    assert_response :success
    @study_file.reload # gotcha in case 'should parse study file' test has already run
    # check all attributes against database
    @study_file.attributes.each do |attribute, value|
      if attribute =~ /_id/
        assert json[attribute] == JSON.parse(value.to_json), "Attribute mismatch: #{attribute} is incorrect, expected #{JSON.parse(value.to_json)} but found #{json[attribute.to_s]}"
      elsif attribute =~ /_at/
        # ignore timestamps as formatting & drift on milliseconds can cause comparison errors
        next
      elsif attribute =~ /cluster_file_info/
        # ignore the $oid field and just look at custom_colors
        assert json[attribute]['custom_colors'] == value['custom_colors']
      else
        assert json[attribute] == value, "Attribute mismatch: #{attribute} is incorrect, expected #{value} but found #{json[attribute.to_s]}"
      end
    end

    # ensure other users cannot access study_file
    sign_in_and_update @other_user
    execute_http_request(:get, api_v1_study_study_file_path(study_id: @study.id, id: @study_file.id), user: @other_user)
    assert_response 403
  end

  # create, update & delete tested together to use new object to avoid delete/update running before create
  test 'should create then update then delete study file' do
    # create study file
    study_file_attributes = {
      study_file: {
        upload_file_name: 'table_1.xlsx',
        upload_content_type: 'application/octet-stream',
        upload_file_size: 41692,
        file_type: 'Other'
      }
    }
    execute_http_request(:post, api_v1_study_study_files_path(study_id: @study.id), request_payload: study_file_attributes)
    assert_response :success
    assert json['name'] == study_file_attributes[:study_file][:upload_file_name], "Did not set name correctly, expected #{study_file_attributes[:study_file][:upload_file_name]} but found #{json['name']}"
    # update study file
    study_file_id = json['_id']['$oid']
    update_attributes = {
      study_file: {
        description: "Test description #{SecureRandom.uuid}"
      }
    }
    execute_http_request(:patch, api_v1_study_study_file_path(study_id: @study.id, id: study_file_id), request_payload: update_attributes)
    assert_response :success
    assert json['description'] == update_attributes[:study_file][:description], "Did not set description correctly, expected #{update_attributes[:study_file][:description]} but found #{json['description']}"
    # delete study file
    execute_http_request(:delete, api_v1_study_study_file_path(study_id: @study.id, id: study_file_id))
    assert_response 204, "Did not successfully delete study file, expected response of 204 but found #{@response.response_code}"
  end

  test 'can update cluster name' do
    cluster_file = @study_file
    update_attributes = {
      study_file: {
        name: 'updated name'
      }
    }
    execute_http_request(:patch, api_v1_study_study_file_path(study_id: @study.id, id: cluster_file._id), request_payload: update_attributes)
    assert_equal 'updated name', json['name']
    assert_equal 'updated name', @study.cluster_groups.first.reload.name
  end


  # create a study file bundle using the study_files_controller method
  test 'should create study file bundle' do
    study_file_bundle_attributes = {
      'files' => [
        { 'name' => 'cluster.tsv', 'file_type' => 'Cluster' },
        { 'name' => 'labels.tsv', 'file_type' => 'Coordinate Labels' }
      ]
    }
    execute_http_request(:post, api_v1_study_study_files_bundle_files_path(study_id: @study.id), request_payload: study_file_bundle_attributes)
    assert_response :success
    assert json['original_file_list'] == study_file_bundle_attributes['files'],
           "Did not set name correctly, expected #{study_file_bundle_attributes['files']} but found #{json['original_file_list']}"
    # delete study file bundle
    study_file_bundle_id = json['_id']['$oid']
    execute_http_request(:delete, api_v1_study_study_file_bundle_path(study_id: @study.id, id: study_file_bundle_id))
    assert_response 204, "Did not successfully delete study file bundle, expected response of 204 but found #{@response.response_code}"
  end

  test 'should parse study file' do
    execute_http_request(:post, parse_api_v1_study_study_file_path(study_id: @study.id, id: @study_file.id))
    assert_response 204
  end

  test 'should enforce edit access restrictions on study files' do
    sign_in_and_update @other_user
    description = "This is the updated description with random seed #{@random_seed}"
    update_attributes = {
      study_file: {
        description: description
      }
    }
    execute_http_request(:patch, api_v1_study_study_file_path(study_id: @study.id, id: @study_file.id.to_s),
                         request_payload: update_attributes, user: @other_user)
    assert_response 403
    @study_file.reload
    refute @study_file.description == description
  end

  # create, update & delete tested together to use new object to avoid delete/update running before create
  test 'should correctly update custom colors' do
    annot1_color_hash = {
      'annotation1': {
        'labelA': '#aabb00',
        'labelB': '#bb2211'
      }
    }.with_indifferent_access
    study_file_attributes = {
      study_file: {
        custom_color_updates: annot1_color_hash.to_json
      }
    }
    execute_http_request(:patch, api_v1_study_study_file_path(study_id: @study.id, id: @study_file.id),
      request_payload: study_file_attributes)
    assert_response :success

    @study_file.reload
    # check that the colors were updated
    assert_equal annot1_color_hash, @study_file.cluster_file_info.custom_colors_as_hash.with_indifferent_access

    annot2_color_hash = {
      'annotation2': {
        'labelA': '#aabb00',
        'labelC': '#bb2211'
      }
    }.with_indifferent_access
    study_file_attributes[:study_file][:custom_color_updates] = annot2_color_hash.to_json
    execute_http_request(:patch, api_v1_study_study_file_path(study_id: @study.id, id: @study_file.id),
      request_payload: study_file_attributes)
    assert_response :success

    @study_file.reload
    # check that the new annotation colors were added, and the previous ones remain
    assert_equal annot2_color_hash.merge(annot1_color_hash), @study_file.cluster_file_info.custom_colors_as_hash.with_indifferent_access

    updated_annot2_color_hash = {
      'annotation1': {
        'labelA': '#333333',
        'labelC': '#999999'
      }
    }.with_indifferent_access
    study_file_attributes[:study_file][:custom_color_updates] = updated_annot2_color_hash.to_json
    execute_http_request(:patch, api_v1_study_study_file_path(study_id: @study.id, id: @study_file.id),
      request_payload: study_file_attributes)
    assert_response :success

    @study_file.reload
    # confirm the annotation1 colors were completely replaced, and annotation2 colors were preserved
    assert_equal updated_annot2_color_hash.merge(annot2_color_hash), @study_file.cluster_file_info.custom_colors_as_hash.with_indifferent_access
  end

  test 'should create and update AnnData file' do
    cluster_frag_id = BSON::ObjectId.new.to_s
    exp_frag_id = BSON::ObjectId.new.to_s
    ann_data_params = {
      study_file: {
        upload_file_name: 'data.h5ad',
        upload_content_type: 'application/octet-stream',
        upload_file_size: 1.megabyte,
        file_type: 'AnnData',
        reference_anndata_file: 'false',
        expression_file_info_attributes: {
          biosample_input_type: 'Whole cell',
          is_raw_counts: false,
          library_preparation_protocol: "10x 5' v3",
          modality: 'Transcriptomic: unbiased',
          raw_counts_associations: ['']
        },
        extra_expression_form_info_attributes: {
          _id: exp_frag_id,
          description: 'expression description',
          y_axis_title: 'log(TPM) expression'
        },
        metadata_form_info_attributes: {
          use_metadata_convention: true
        },
        cluster_form_info_attributes: {
          _id: cluster_frag_id,
          name: 'UMAP',
          obsm_key_name: 'X_umap',
          description: 'UMAP cluster'
        }
      }
    }

    execute_http_request(:post,
                         api_v1_study_study_files_path(study_id: @study.id),
                         request_payload: ann_data_params)
    assert_response :success
    ann_data = StudyFile.find_by(study_id: @study.id, upload_file_name: 'data.h5ad')
    assert ann_data.present?
    assert ann_data.ann_data_file_info.present?
    assert_not ann_data.ann_data_file_info.reference_file?
    data_fragments = ann_data.ann_data_file_info.data_fragments
    assert_equal 2, data_fragments.size
    # update file to test ann_data_file_info_attributes form structure
    update_attributes = {
      study_file: {
        description: 'updated',
        ann_data_file_info_attributes: {
          data_fragments:
            [
              { _id: cluster_frag_id, name: 'UMAP', obsm_key_name: 'X_umap', description: 'updated' },
              { _id: exp_frag_id, y_axis_title: 'log(TPM) expression', description: 'updated' }
            ]
        }
      }
    }
    execute_http_request(:patch,
                         api_v1_study_study_file_path(study_id: @study.id, id: ann_data.id.to_s),
                         request_payload: update_attributes)
    assert_response :success
    ann_data.reload
    assert_equal 'updated', ann_data.description
    ann_data.ann_data_file_info.data_fragments.each do |fragment|
      assert_equal 'updated', fragment[:description]
    end
  end
end
