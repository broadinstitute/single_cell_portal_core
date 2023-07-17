require 'test_helper'

class ClusterCacheServiceTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Test Cache Study',
                               user: @user,
                               test_array: @@studies_to_clean)
    @study_cluster_file_1 = FactoryBot.create(:cluster_file,
                                              name: 'cluster_1.txt', study: @study,
                                              cell_input: {
                                                x: [1, 4 ,6],
                                                y: [7, 5, 3],
                                                z: [2, 8, 9],
                                                cells: ['A', 'B', 'C']
                                              },
                                              x_axis_label: 'PCA 1',
                                              y_axis_label: 'PCA 2',
                                              z_axis_label: 'PCA 3',
                                              cluster_type: '3d',
                                              annotation_input: [
                                                {name: 'Category', type: 'group', values: ['bar', 'bar', 'baz']},
                                                {name: 'Intensity', type: 'numeric', values: [1.1, 2.2, 3.3]}
                                              ])

    @study_metadata_file = FactoryBot.create(:metadata_file,
                                             name: 'metadata.txt', study: @study,
                                             cell_input: ['A', 'B', 'C'],
                                             annotation_input: [
                                               {name: 'species', type: 'group', values: ['dog', 'cat', 'dog']},
                                               {name: 'disease', type: 'group', values: ['none', 'none', 'measles']}
                                             ])

    defaults = {
      cluster: 'cluster_1.txt',
      annotation: 'species--group--study'
    }
    @study.update(default_options: defaults)
  end

  test 'should format request path' do
    # no parameters
    expected_site_path = '/single_cell'
    formatted_path = ClusterCacheService.format_request_path(:site_path)
    assert_equal expected_site_path, formatted_path
    # path-level parameters
    expected_view_study_path = "/single_cell/study/#{@study.accession}/#{@study.url_safe_name}"
    formatted_study_path = ClusterCacheService.format_request_path(:view_study_path,
                                                                   @study.accession, @study.url_safe_name)
    assert_equal expected_view_study_path, formatted_study_path
    # query string-level parameters
    cluster = @study.cluster_groups.first
    expected_cluster_path = "/single_cell/api/v1/studies/#{@study.accession}/clusters/#{cluster.name}?annotation_name=species" \
                            "&annotation_scope=study&annotation_type=group"
    formatted_cluster_path = ClusterCacheService.format_request_path(:api_v1_study_cluster_path,
                                                                     @study.accession, cluster_name: cluster.name,
                                                                     annotation_name: 'species', annotation_scope: 'study',
                                                                     annotation_type: 'group')
    assert_equal expected_cluster_path, formatted_cluster_path
  end

  test 'should cache study defaults' do
    cluster = @study.default_cluster
    annotation = @study.default_annotation
    annotation_name, annotation_type, annotation_scope = annotation.split('--')
    default_params = { cluster_name: '_default', fields: 'coordinates,cells,annotation' }.with_indifferent_access
    expected_default_path = RequestUtils.get_cache_path(
      "/single_cell/api/v1/studies/#{@study.accession}/clusters/_default",
      default_params
    )
    named_params = { cluster_name: cluster.name, fields: 'coordinates,cells,annotation',
                     annotation_name: annotation_name, annotation_type: annotation_type,
                     annotation_scope: annotation_scope, subsample: 'all' }.with_indifferent_access
    expected_named_path = RequestUtils.get_cache_path(
      "/single_cell/api/v1/studies/#{@study.accession}/clusters/#{cluster.name}",
      named_params
    )
    ClusterCacheService.cache_study_defaults(@study)
    assert Rails.cache.exist?(expected_default_path), "did not find default cache entry at #{expected_default_path}"
    assert Rails.cache.exist?(expected_named_path), "did not find named cache entry at #{expected_named_path}"
  end
end
