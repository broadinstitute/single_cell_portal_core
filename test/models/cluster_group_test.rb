require 'test_helper'

class ClusterGroupTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Basic Viz',
                               user: @user,
                               test_array: @@studies_to_clean)
    @cluster_file = FactoryBot.create(:cluster_file,
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

    @cluster = @study.cluster_groups.first
  end

  test 'should not visualize unique group annotations over 100' do
    annotation_values = []
    300.times { annotation_values << SecureRandom.uuid }
    cell_annotation = {name: 'Group Annotation', type: 'group', values: annotation_values}
    cluster = ClusterGroup.new(name: 'Group Count Test', cluster_type: '2d', cell_annotations: [cell_annotation], study: @study)
    can_visualize = cluster.can_visualize_cell_annotation?(cell_annotation)
    assert !can_visualize, "Should not be able to visualize group cell annotation with more than 200 unique values: #{can_visualize}"

    # check study overrides are respected
    @study.default_options[:override_viz_limit_annotations] = [cell_annotation[:name]]
    can_visualize = cluster.can_visualize_cell_annotation?(cell_annotation)
    assert can_visualize, "Should be able to visualize group cell annotation with more that 200 unique values if override is present"

    # check numeric annotations are still fine
    new_cell_annotation = {name: 'Numeric Annotation', type: 'numeric', values: []}
    cluster.cell_annotations << new_cell_annotation
    can_visualize_numeric  = cluster.can_visualize_cell_annotation?(new_cell_annotation)
    assert can_visualize_numeric, "Should be able to visualize numeric cell annotation at any level: #{can_visualize_numeric}"
  end

  test 'should set point count on cluster group' do
    # ensure cluster point count was set by FactoryBot
    assert_equal 3, @cluster.points

    @cluster.update!(points: nil)
    assert_nil @cluster.points

    # test both return value and assignment for set_point_count!
    points = @cluster.set_point_count!
    assert_equal 3, points
    assert_equal 3, @cluster.points
  end

  test 'should generate cell index' do
    study_cells = 'A'.upto('zzz').to_a
    coords = study_cells.each_index.to_a
    FactoryBot.create(:cluster_file,
                      study: @study,
                      name: 'identical.txt',
                      cell_input: {
                        x: coords,
                        y: coords,
                        cells: study_cells
                      })
    identical_cluster = @study.cluster_groups.by_name('identical.txt')
    index = identical_cluster.cell_name_index(study_cells)
    assert index.empty?
    cluster_cells = study_cells.take(10_000).shuffle
    cluster_coords = cluster_cells.each_index.to_a
    FactoryBot.create(:cluster_file,
                      study: @study,
                      name: 'different.txt',
                      cell_input: {
                        x: cluster_coords,
                        y: cluster_coords,
                        cells: cluster_cells
                      })
    different_cluster = @study.cluster_groups.by_name('different.txt')
    index = different_cluster.cell_name_index(study_cells)
    assert index.is_a?(Array)
    expected_index = cluster_cells.map { |c| study_cells.index(c) }
    assert_equal expected_index, index
  end

  test 'uses default cell index' do
    cells = "A".upto("Z").to_a
    enumerator = 0.upto(25)
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Default Cell Array',
                              user: @user,
                              test_array: @@studies_to_clean)
    FactoryBot.create(:metadata_file,
                      study:,
                      name: 'metadata.txt',
                      cell_input: cells)
    FactoryBot.create(:cluster_file,
                      study:,
                      name: 'cluster.txt',
                      cell_input: {
                        x: enumerator.to_a,
                        y: enumerator.to_a,
                        cells:
                      })
    cluster = study.cluster_groups.first
    assert_equal enumerator.to_a, cluster.cell_index_array.to_a
    assert cluster.use_default_index
  end
end

