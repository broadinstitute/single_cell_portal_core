require 'test_helper'

class ClusterVizServiceTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Test Cluster Study',
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

    @study_cluster_file_2 = FactoryBot.create(:cluster_file,
                                              name: 'cluster_2.txt', study: @study,
                                              cell_input: {
                                                  x: [1, 2, 3],
                                                  y: [4, 5, 6],
                                                  cells: ['D', 'E', 'F']
                                              })

    @study_cluster_file_3 = FactoryBot.create(:cluster_file,
                                              name: 'cluster_3.txt', study: @study,
                                              cell_input: {
                                                x: [1, 2, 3],
                                                y: [4, 5, 6],
                                                cells: ['D', 'E', 'F']
                                              },
                                              annotation_input: [
                                                {name: 'Blanks', type: 'group', values: ['bar', 'bar', '']}
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

  test 'should load cluster' do
    # test default cluster w/ empty params
    default_cluster = @study.default_cluster
    loaded_cluster = ClusterVizService.get_cluster_group(@study, {})
    assert_equal default_cluster, loaded_cluster,
                 "Did not correctly load default cluster; #{default_cluster.name} != #{loaded_cluster.name}"

    # test loading by params
    cluster_name = 'cluster_2.txt'
    params = {cluster: cluster_name}
    expected_cluster = @study.cluster_groups.by_name(cluster_name)
    other_cluster = ClusterVizService.get_cluster_group(@study, params)
    assert_equal expected_cluster, other_cluster,
                 "Did not correctly load expected cluster; #{expected_cluster.name} != #{other_cluster.name}"
  end

  test 'should load all clusters' do
    # expect to return all non-spatial cluster names
    clusters = @study.clustering_files.where(:is_spatial.ne => true).pluck(:name)
    all_clusters = ClusterVizService.load_cluster_group_options(@study)
    assert_equal clusters, all_clusters, "Did not load correct clusters; #{clusters} != #{all_clusters}"
  end

  test 'should load cluster annotation options' do
    expected_options = {
        'Study Wide' => [
            %w(species species--group--study), %w(disease disease--group--study)
        ],
        'Cluster-Based' => [
            %w(Category Category--group--cluster), %w(Intensity Intensity--numeric--cluster)
        ]
    }
    annotation_opts = ClusterVizService.load_cluster_group_annotations(@study, @study.default_cluster, @user)
    assert_equal expected_options, annotation_opts
  end

  test 'should load spatial clusters' do
    spatial_name = 'spatial.txt'
    FactoryBot.create(:cluster_file,
                      name: spatial_name, study: @study,
                      is_spatial: true,
                      cell_input: {
                          x: [1, 2, 3],
                          y: [4, 5, 6],
                          cells: ['Q', 'E', 'D']
                      })
    loaded_option = ClusterVizService.load_spatial_options(@study)
    assert_equal [{name: 'spatial.txt', associated_clusters: []}], loaded_option
  end

  test 'should load subsampling options' do
    # create a cluster w/ 2K cells
    coordinates = 1.upto(2000).to_a
    cells = coordinates.map {|n| "cell_#{n}"}
    cluster_name = 'cluster_subsample.txt'
    FactoryBot.create(:cluster_file,
                      name: cluster_name, study: @study,
                      cell_input: {
                          x: coordinates,
                          y: coordinates,
                          cells: cells
                      })
    cluster = @study.cluster_groups.by_name(cluster_name)
    options = ClusterVizService.subsampling_options(cluster)
    assert_equal [1000], options
  end

  test 'should load cluster coordinates' do
    cluster = @study.default_cluster
    metadata = @study.cell_metadata.by_name_and_type('species', 'group')
    annotation = {name: metadata.name, type: metadata.annotation_type, scope: 'study'}
    viz_data = ClusterVizService.load_cluster_group_data_array_points(@study, cluster, annotation)

    assert_equal [:annotations, :cells, :x, :y, :z], viz_data.keys.sort
    assert_equal ["A", "B", "C"], viz_data[:cells]
    assert_equal [1, 4, 6], viz_data[:x]
    assert_equal [7, 5, 3], viz_data[:y]
    assert_equal [2, 8, 9], viz_data[:z]
    assert_equal ["dog", "cat", "dog"], viz_data[:annotations]
  end

  test 'should include/exclude specified fields' do
    cluster = @study.default_cluster
    metadata = @study.cell_metadata.by_name_and_type('species', 'group')
    annotation = {name: metadata.name, type: metadata.annotation_type, scope: 'study'}
    viz_data = ClusterVizService.load_cluster_group_data_array_points(@study, cluster, annotation, include_coords: false)
    assert_equal [:annotations, :cells], viz_data.keys.sort
    assert_equal ["A", "B", "C"], viz_data[:cells]
    viz_data = ClusterVizService.load_cluster_group_data_array_points(@study, cluster, annotation, include_cells: false)
    assert_equal [:annotations, :x, :y, :z], viz_data.keys.sort
    assert_equal ["dog", "cat", "dog"], viz_data[:annotations]
    viz_data = ClusterVizService.load_cluster_group_data_array_points(@study, cluster, annotation, include_annotations: false)
    assert_equal [:cells, :x, :y, :z], viz_data.keys.sort
    assert_equal [1, 4, 6], viz_data[:x]
  end

  test 'should load cluster coordinates with blank annotations' do
    cluster = @study.cluster_groups.by_name('cluster_3.txt')
    annotation = AnnotationVizService.get_selected_annotation(@study, cluster: cluster, annot_name: 'Blanks', annot_type: 'group', annot_scope: 'cluster')
    viz_data = ClusterVizService.load_cluster_group_data_array_points(@study, cluster, annotation)
    assert_equal ["bar", "bar", "--Unspecified--"], viz_data[:annotations]
    assert_equal ["D", "E", "F"], viz_data[:cells]
  end

  test 'should load coordinate labels as annotations' do
    cluster = @study.default_cluster
    FactoryBot.create(:coordinate_label_file,
                      cluster: cluster, name: 'coordinate_labels.txt', study: @study,
                      label_input: {
                          x: [1, 2, 3],
                          y: [4, 5, 6],
                          z: [7, 8, 9],
                          text: ['Group 1', 'Group 2', 'Group 3']
                      })
    labels = ClusterVizService.load_cluster_group_coordinate_labels(cluster)
    assert_equal 3, labels.size, "Did not find correct number of labels; expected 3 but found #{labels.size}"
    selected_label = labels.first
    assert_equal 1, selected_label[:x]
    assert_equal 4, selected_label[:y]
    assert_equal 7, selected_label[:z]
    assert_equal 'Group 1', selected_label[:text]
    assert selected_label[:font].present?
    font_keys = [:family, :size, :color]
    assert_equal font_keys, selected_label[:font].keys
  end

  test 'should load axis labels' do
    cluster = @study.default_cluster
    axis_labels = ClusterVizService.load_axis_labels(cluster)
    axis_labels.values.each_with_index do |label, index|
      expected_label = "PCA #{index + 1}"
      assert_equal expected_label, label
    end
  end

  test 'should compute aspect ratio for predefined range' do
    cluser_file_with_range = 'cluster_ranged.txt'
    FactoryBot.create(:cluster_file,
                      name: cluser_file_with_range, study: @study,
                      cluster_type: '3d',
                      x_axis_min: 0,
                      x_axis_max: 4,
                      y_axis_min: 3,
                      y_axis_max: 7,
                      z_axis_min: 6,
                      z_axis_max: 10,
                      cell_input: {
                          x: [1, 2, 3],
                          y: [4, 5, 6],
                          z: [7, 8, 9],
                          cells: ['G', 'H', 'I']
                      })
    cluster = @study.cluster_groups.by_name(cluser_file_with_range)

    # as absolute extent for each axis is the same (4), this should enforce a cube aspect
    expected_aspect = {mode: 'cube', x: 1.0, y: 1.0, z: 1.0}
    computed_aspect = ClusterVizService.compute_aspect_ratios(cluster.domain_ranges)
    assert_equal expected_aspect, computed_aspect
  end

  # ensure default value for cluster_group.points will prevent NoMethodError when getting subsampling options
  # before cluster_group.set_point_count! is called at the end of successful ingest
  test 'should fallback to default points for new cluster' do
    new_cluster = @study.cluster_groups.build(name: 'New Cluster', cluster_type: '2d')
    assert_equal 0, new_cluster.points
    assert_empty ClusterVizService.subsampling_options(new_cluster)
    assert_nil ClusterVizService.default_subsampling(new_cluster)
  end

  test 'should return map of annotation labels to cells for a cluster' do
    cluster = ClusterGroup.find_by(study: @study, study_file: @study_cluster_file_1)
    study_map = {
      dog: %w[A C],
      cat: %w[B]
    }.with_indifferent_access
    assert_equal study_map, ClusterVizService.cells_by_annotation_label(cluster, 'species', 'study')

    cluster_map = {
      bar: %w[A B],
      baz: %w[C]
    }.with_indifferent_access
    assert_equal cluster_map, ClusterVizService.cells_by_annotation_label(cluster, 'Category', 'cluster')
  end

  test 'should retrieve clustering information for AnnData files' do
    cluster_name = 'x_tsne'
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'AnnData Cluster Test',
                              user: @user,
                              test_array: @@studies_to_clean)
    FactoryBot.create(:ann_data_file,
                      name: 'data.h5ad',
                      study:,
                      cell_input: %w[A B C D],
                      annotation_input: [
                        { name: 'disease', type: 'group', values: %w[cancer cancer normal normal] }
                      ],
                      coordinate_input: [
                        { cluster_name => { x: [1, 2, 3, 4], y: [5, 6, 7, 8] } }
                      ])
    assert_equal [cluster_name], ClusterVizService.load_cluster_group_options(study)
  end
end
