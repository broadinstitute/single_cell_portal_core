require 'test_helper'
require 'api_test_helper'
require 'includes_helper'

class ExploreControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @user2 = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'Basic Explore',
                                     public: false,
                                     user: @user,
                                     test_array: @@studies_to_clean)
    @basic_study_cluster_file = FactoryBot.create(:cluster_file,
                                                  name: 'clusterA.txt',
                                                  file_type: 'Cluster',
                                                  study: @basic_study,
                                                  annotation_input: [{name: 'foo', type: 'group', values: ['bar', 'bar', 'baz']}])
    cluster = @basic_study.cluster_groups.by_name('clusterA.txt')
    cluster.update(has_image_cache: true)

    @spatial_study_cluster_file = FactoryBot.create(:cluster_file,
                                                    name: 'spatialA.txt',
                                                    file_type: 'Cluster',
                                                    study: @basic_study,
                                                    is_spatial: true)

    @empty_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'Empty study',
                                     user: @user,
                                     test_array: @@studies_to_clean)

    @public_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'Public Explore',
                                     public: true,
                                     user: @user,
                                     test_array: @@studies_to_clean)
    @public_study_cluster_file = FactoryBot.create(:cluster_file,
                                                  name: 'clusterP.txt',
                                                  file_type: 'Cluster',
                                                  study: @public_study,
                                                  annotation_input: [{name: 'foo', type: 'group', values: ['bar', 'bar', 'baz']}])
    user_annot_data = {
      label1: {name: 'label1', values: 'cell1,cell2'},
      label2: {name: 'label2', values: 'cell3,cell4'}
    }
    UserAnnotationService.create_user_annotation(@public_study, 'user_annot',
      user_annot_data, 'clusterP.txt', 'foo--group--cluster', nil, @user)
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test 'should enforce view permissions' do
    user2 = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    sign_in_and_update user2
    execute_http_request(:get, api_v1_study_explore_path(@basic_study), user: user2)
    assert_equal 403, response.status

    execute_http_request(:get, cluster_options_api_v1_study_explore_path(@basic_study), user: user2)
    assert_equal 403, response.status

    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_explore_path(@basic_study))
    assert_equal 200, response.status

    execute_http_request(:get, cluster_options_api_v1_study_explore_path(@basic_study))
    assert_equal 200, response.status
  end

  test 'should get basic study visualization data' do
    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_explore_path(@basic_study))
    assert_response :success

    cluster_name = 'clusterA.txt'
    assert_equal [cluster_name], json['clusterGroupNames']
    assert_equal [{"name" => 'spatialA.txt', "associated_clusters" => []}], json['spatialGroups']
    assert_includes json['hasImageCache'], cluster_name

    execute_http_request(:get, api_v1_study_explore_path(@empty_study))
    assert_equal [], json['clusterGroupNames']
  end

  test 'should get annotation listings' do
    sign_in_and_update @user
    execute_http_request(:get, cluster_options_api_v1_study_explore_path(@basic_study))
    assert_response :success

    assert_equal 'clusterA.txt', json['default_cluster']
    expected_annotations = [
      {
        name: 'foo', type: 'group', values: %w[bar baz], scope: 'cluster', cluster_name: 'clusterA.txt',
        is_differential_expression_enabled: false
      }.with_indifferent_access
    ]
    assert_equal expected_annotations, json['annotations']
    assert_equal({"clusterA.txt"=>[], "spatialA.txt"=>[]}, json['subsample_thresholds'])

    execute_http_request(:get, cluster_options_api_v1_study_explore_path(@empty_study))
    assert_equal [], json['annotations']
  end

  test 'should get user-specific study info' do
    sign_in_and_update @user
    execute_http_request(:get, study_user_info_api_v1_study_explore_path(@public_study))
    assert_response :success
    assert_equal 2, json['annotations'].length
    assert_equal 1, json['annotations'].select{|a| a['name'] == 'user_annot'}.length
    assert_equal true, json['canEdit']

    sign_in_and_update @user2
    execute_http_request(:get, study_user_info_api_v1_study_explore_path(@public_study), user: @user2)
    assert_response :success
    assert_equal 1, json['annotations'].length
    assert_equal 0, json['annotations'].select{|a| a['name'] == 'user_annot'}.length
    assert_equal false, json['canEdit']

    execute_http_request(:get, study_user_info_api_v1_study_explore_path(@public_study), user: nil)
    assert_response :success
    assert_equal 1, json['annotations'].length
    assert_equal 0, json['annotations'].select{|a| a['name'] == 'user_annot'}.length
    assert_equal false, json['canEdit']
  end

  test 'should handle invalid study id' do
    sign_in_and_update @user
    execute_http_request(:get, cluster_options_api_v1_study_explore_path('SCP1234567'))
    assert_equal 404, response.status
  end
end
