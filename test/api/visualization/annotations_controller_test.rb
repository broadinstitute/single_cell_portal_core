require 'test_helper'
require 'api_test_helper'
require 'includes_helper'

class AnnotationsControllerTest < ActionDispatch::IntegrationTest

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
                                                  annotation_input: [{name: 'foo', type: 'group', values: ['bar', 'bar', 'baz']}])

    @basic_study_metadata_file = FactoryBot.create(:metadata_file,
                                                   name: 'metadata.txt',
                                                   study: @basic_study,
                                                   cell_input: ['A', 'B', 'C'],
                                                   annotation_input: [
                                                     {name: 'species', type: 'group', values: ['dog', 'cat', 'dog']},
                                                     {name: 'disease', type: 'group', values: ['none', 'none', 'measles']}
                                                   ])

    marker_cluster_list = %w(Cluster1 Cluster2 Cluster3)
    @gene_list_file = FactoryBot.create(:gene_list,
                                       study: @basic_study,
                                       name: 'marker_gene_list.txt',
                                       list_name: 'Marker List 1',
                                       clusters_input: marker_cluster_list,
                                       gene_scores_input: [
                                         {
                                           'PTEN' => Hash[marker_cluster_list.zip([1,2,3])]
                                         },
                                         {
                                           'AGPAT2' => Hash[marker_cluster_list.zip([4,5,6])]
                                         }
                                       ])
    @gene_list_file_2 = FactoryBot.create(:gene_list,
                                         study: @basic_study,
                                         name: 'marker_gene_list_2.txt',
                                         list_name: 'gene_list.with.periods',
                                         clusters_input: marker_cluster_list,
                                         gene_scores_input: [
                                           {
                                             'APOE' => Hash[marker_cluster_list.zip([9,8,7])]
                                           },
                                           {
                                             'ACTA2' => Hash[marker_cluster_list.zip([6,5,4])]
                                           }
                                         ])
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test 'methods should check view permissions' do
    user2 = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    sign_in_and_update user2
    execute_http_request(:get, api_v1_study_annotations_path(@basic_study), user: user2)
    assert_equal 403, response.status

    execute_http_request(:get, api_v1_study_annotation_path(@basic_study, 'foo'), user: user2)
    assert_equal 403, response.status

    execute_http_request(:get, cell_values_api_v1_study_annotation_path(@basic_study, 'foo'), user: user2)
    assert_equal 403, response.status

    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_annotations_path(@basic_study, 'foo'), user: @user)
    assert_equal 200, response.status
  end

  test 'index should return list of annotations' do
    empty_study = FactoryBot.create(:detached_study,
                                    user: @user,
                                    name_prefix: 'Empty Annotation Study',
                                    test_array: @@studies_to_clean)
    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_annotations_path(@basic_study))
    assert_equal 3, json.length
    assert_equal(%w[species disease foo], json.map { |annot| annot['name'] })
    expected_annotation = {
      name: 'species', type: 'group', values: %w[dog cat], scope: 'study', is_differential_expression_enabled: false
    }.with_indifferent_access
    assert_equal(expected_annotation, json[0])

    execute_http_request(:get, api_v1_study_annotations_path(empty_study))
    assert_equal [], json
  end

  test 'show should fetch a single annotation' do
    sign_in_and_update @user
    execute_http_request(:get,
                         api_v1_study_annotation_path(@basic_study,
                                                      'foo',
                                                      params: {annotation_scope: 'cluster',
                                                               annotation_type: 'group',
                                                               cluster: 'clusterA.txt'}))
    assert_equal json['name'], 'foo'
    execute_http_request(:get, api_v1_study_annotation_path(@basic_study, 'nonExistentAnnotation'))
    # returns the default annotation if it's not found by name/type
    assert_equal 'species', json['name']
  end

  test 'cell_values should return visualization tsv' do
    sign_in_and_update @user
    execute_http_request(:get,
                         cell_values_api_v1_study_annotation_path(@basic_study,
                                                                  'foo',
                                                                  params: {
                                                                    annotation_scope: 'cluster',
                                                                    annotation_type: 'group',
                                                                    cluster: 'clusterA.txt'
                                                                  })
    )
    assert_equal json, "NAME\tfoo\nA\tbar\nB\tbar\nC\tbaz"
  end

  test 'should load gene list by name' do
    sign_in_and_update @user
    # normal request
    execute_http_request(:get, api_v1_study_annotations_gene_list_path(@basic_study, 'Marker List 1'))
    assert_response :success

    # request w/ periods in name
    execute_http_request(:get, api_v1_study_annotations_gene_list_path(@basic_study, 'gene_list.with.periods'))
    assert_response :success
  end

  test 'should get annotation facets' do
    sign_in_and_update @user
    annotations = 'species--group--study,disease--group--study'
    facet_params = { cluster: 'clusterA.txt', annotations: }
    execute_http_request(:get, api_v1_study_annotations_facets_path(@basic_study, **facet_params))
    assert_response :success
    assert json['cells'].size == 3
    expected_facets = [
      { annotation: 'species--group--study', groups: %w[dog cat] }.with_indifferent_access,
      { annotation: 'disease--group--study', groups: %w[none measles] }.with_indifferent_access
    ]
    # test validations
    assert_equal expected_facets, json['facets']
    execute_http_request(:get, api_v1_study_annotations_facets_path(
      @basic_study, cluster: 'does-not-exist', annotations: ''
    ))
    assert_response :not_found
    execute_http_request(:get, api_v1_study_annotations_facets_path(
      @basic_study, cluster: 'clusterA.txt',  annotations: 'foo--numeric--study'
    ))
    assert_response :bad_request
    execute_http_request(:get, api_v1_study_annotations_facets_path(
      @basic_study, cluster: 'clusterA.txt', annotations: 'not-found--group--study'
    ))
    assert_response :not_found
  end

  test 'should load requested facet annotations' do
    annotation_param = 'species--group--study,disease--group--study'
    cluster = @basic_study.cluster_groups.by_name('clusterA.txt')
    annotations = Api::V1::Visualization::AnnotationsController.get_facet_annotations(
      @basic_study, cluster, annotation_param
    )
    assert_equal 2, annotations.size
    expected_annotations = @basic_study.cell_metadata.map do |meta|
      {
        name: meta.name, type: meta.annotation_type, scope: 'study', values: meta.values,
        identifier: meta.annotation_select_value
      }
    end
    assert_equal expected_annotations, annotations
    assert_empty Api::V1::Visualization::AnnotationsController.get_facet_annotations(
      @basic_study, cluster, 'does-not-exist--group--study'
    )
  end

  test 'should convert annotation identifiers to hash' do
    expected = { annot_name: 'species', annot_type: 'group', annot_scope: 'study' }
    assert_equal expected,
                 Api::V1::Visualization::AnnotationsController.convert_annotation_param('species--group--study')
  end
end
