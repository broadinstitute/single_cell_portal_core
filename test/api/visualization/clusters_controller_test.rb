require 'test_helper'
require 'api_test_helper'
require 'includes_helper'

class ClustersControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'Basic Cluster Study',
                                     public: false,
                                     user: @user,
                                     test_array: @@studies_to_clean)
    @basic_study_cluster_file = FactoryBot.create(:cluster_file,
                                                  name: 'clusterA.txt',
                                                  study: @basic_study,
                                                  cell_input: {
                                                     x: [1, 4 ,6],
                                                     y: [7, 5, 3],
                                                     cells: ['A', 'B', 'C']
                                                  },
                                                  annotation_input: [{name: 'foo', type: 'group', values: ['bar', 'bar', 'baz']},
                                                                     {name: 'intensity', type: 'numeric', values: [1, 2, 5]}])

    @basic_study_metadata_file = FactoryBot.create(:metadata_file,
                                                   name: 'metadata.txt',
                                                   study: @basic_study,
                                                   cell_input: ['A', 'B', 'C'],
                                                   annotation_input: [
                                                     {name: 'species', type: 'group', values: ['dog', 'cat', 'dog']},
                                                     {name: 'disease', type: 'group', values: ['none', 'none', 'measles']}
                                                   ])
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test 'enforces view permissions' do
    user2 = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    sign_in_and_update user2
    execute_http_request(:get, api_v1_study_clusters_path(@basic_study), user: user2)
    assert_equal 403, response.status

    execute_http_request(:get, cluster_options_api_v1_study_explore_path(@basic_study), user: user2)
    assert_equal 403, response.status

    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_clusters_path(@basic_study))
    assert_equal 200, response.status

    execute_http_request(:get, cluster_options_api_v1_study_explore_path(@basic_study))
    assert_equal 200, response.status
  end

  test 'index should return list of cluster names' do
    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_clusters_path(@basic_study))
    assert_equal ["clusterA.txt"], json

    empty_study = FactoryBot.create(:detached_study,
                                    name_prefix: 'Empty Cluster Study',
                                    user: @user,
                                    test_array: @@studies_to_clean)
    execute_http_request(:get, api_v1_study_clusters_path(empty_study))
    assert_equal [], json
  end

  test 'show should return visualization information' do
    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_cluster_path(@basic_study, 'clusterA.txt'))
    assert_equal({
      "data"=>{
        "annotations"=>["bar", "bar", "baz"],
        "cells"=>["A", "B", "C"],
        "x"=>[1, 4, 6],
        "y"=>[7, 5, 3]
      },
      "pointSize"=>3,
      "customColors"=>{},
      "clusterFileId"=>@basic_study_cluster_file.id.to_s,
      "userSpecifiedRanges"=>nil,
      "showClusterPointBorders"=>false,
      "description"=>nil,
      "is3D"=>false,
      "isSubsampled"=>false,
      "isAnnotatedScatter"=>false,
      "isCorrelatedScatter"=>false,
      "isSpatial"=>false,
      "numPoints"=>3,
      "axes"=>{"titles"=>{"x"=>"X", "y"=>"Y", "z"=>"Z", "magnitude" => "Expression"}, "aspects"=>nil},
      "hasCoordinateLabels"=>false,
      "coordinateLabels"=>[],
      "pointAlpha"=>1.0,
      "cluster"=>"clusterA.txt",
      "genes"=>[],
      "annotParams"=>{"name"=>"foo", "type"=>"group", "scope"=>"cluster", "values"=>["bar", "baz"], "identifier"=>"foo--group--cluster"},
      "subsample"=>"all",
      "isSplitLabelArrays"=>false,
      "consensus"=>nil,
      "externalLink"=>{"url"=>nil, "title"=>nil, "description"=>nil}
    }, json)
  end

  test 'show should handle numeric clusters' do
    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_cluster_path(@basic_study, 'clusterA.txt', {annotation_name: 'intensity', annotation_scope: 'cluster', annotation_type: 'numeric'}))
    assert_equal([1, 2, 5], json['data']['annotations'])
    assert_equal('numeric', json['annotParams']['type'])
  end

  test 'should load clusters with slashes in name' do
    slash_study = FactoryBot.create(:detached_study,
                                    name_prefix: 'Cluster Slash Study',
                                    user: @user,
                                    test_array: @@studies_to_clean)
    cluster_with_slash = FactoryBot.create(:cluster_file,
                                           name: 'data/cluster_with_slash.txt',
                                           study: slash_study,
                                           cell_input: {
                                             x: [1, 2 , 3, 4],
                                             y: [5, 6, 7, 8],
                                             cells: %w(A B C D)
                                           },
                                           annotation_input: [{name: 'category', type: 'group', values: ['bar', 'bar', 'baz', 'bar']}])

    # slash must be URL encoded with %2F, and URL constructed manually as the path helper cannot resolve cluster_name param
    # with a slash due to the route constraint of {:cluster_name=>/[^\/]+/}; using route helper api_v1_study_cluster_path()
    # with the params of cluster_name: 'data/cluster_with_slash.txt' or cluster_name: 'data%2Fcluster_with_slash' does not work
    cluster_name = 'data%2Fcluster_with_slash.txt'
    basepath = "/single_cell/api/v1/studies/#{slash_study.accession}/clusters/#{cluster_name}"
    query_string = '?annotation_name=category&annotation_type=group&annotation_scope=cluster'
    url = basepath + query_string
    execute_http_request(:get, url)
    assert_response :success
    assert_equal 4, json['numPoints']
    assert_equal ['bar', 'bar', 'baz', 'bar'], json['data']['annotations']

    # assert that non-encoded cluster names do not load correct cluster
    # using path helper here results in cluster_name not being decoded properly by clusters_controller.rb
    # and is interpreted literally as data%2Fcluster_with_slash.txt, rather than data/cluster_with_slash.txt
    execute_http_request(:get, api_v1_study_cluster_path(slash_study.accession, cluster_name,
                                                         annotation_name: 'category', annotation_type: 'group',
                                                         annotation_scope: 'cluster'))
    assert_response :not_found
    expected_error = {"error"=>"No cluster named data%2Fcluster_with_slash.txt could be found"}
    assert_equal expected_error, json
  end

  test 'should set aspect ratio and domains when provided' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Domain Range Study',
                              user: @user,
                              test_array: @@studies_to_clean)
    cluster_name = 'cluster_domains.txt'
    cluster_file = FactoryBot.create(:cluster_file,
                                     name: cluster_name,
                                     study: study,
                                     cell_input: {
                                       x: [1, 2 , 3, 4],
                                       y: [3, 4, 5, 6],
                                       z: [5, 6, 7, 8],
                                       cells: %w(A B C D)
                                     },
                                     annotation_input: [
                                       {name: 'species', type: 'group', values: ['dog', 'cat', 'dog']}
                                     ],
                                     x_axis_min: 0, x_axis_max: 5,
                                     y_axis_min: 2, y_axis_max: 7,
                                     z_axis_min: 4, z_axis_max: 9
    )
    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_cluster_path(study, cluster_name))
    # aspect should be 'cube' as domain range of each axis is equal (5)
    expected_aspect = {
      mode: 'cube', x: 1.0, y: 1.0, z: 1.0
    }.with_indifferent_access
    expected_ranges = {
      x: [cluster_file.x_axis_min, cluster_file.x_axis_max],
      y: [cluster_file.y_axis_min, cluster_file.y_axis_max],
      z: [cluster_file.z_axis_min, cluster_file.z_axis_max]
    }.with_indifferent_access
    viz_data = json.with_indifferent_access

    assert viz_data.dig(:is3D)
    assert_equal expected_aspect, viz_data.dig(:axes, :aspects)
    assert_equal expected_ranges, viz_data.dig(:userSpecifiedRanges)
  end
end
