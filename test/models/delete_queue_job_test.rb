require 'test_helper'

class DeleteQueueJobTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'DeleteQueue Test',
                                     user: @user,
                                     test_array: @@studies_to_clean)

    @basic_study_exp_file = FactoryBot.create(:study_file,
                                              name: 'dense.txt',
                                              file_type: 'Expression Matrix',
                                              study: @basic_study)


    @pten_gene = FactoryBot.create(:gene_with_expression,
                                   name: 'PTEN',
                                   study_file: @basic_study_exp_file,
                                   expression_input: [['A', 0],['B', 3],['C', 1.5]])
    @basic_study_exp_file.build_expression_file_info(is_raw_counts: false, library_preparation_protocol: 'MARS-seq',
                                                     modality: 'Transcriptomic: unbiased', biosample_input_type: 'Whole cell')
    @basic_study_exp_file.save!
  end

  # test to ensure expression matrix files with "invalid" expression_file_info documents can still be deleted
  # this happens when attributes on nested documents have new constraints placed after creation, like additional
  # validations or fields
  test 'should allow deletion of legacy expression matrices' do
    assert @basic_study_exp_file.valid?,
           "Expression file should be valid but is not: #{@basic_study_exp_file.errors.full_messages}"
    assert @basic_study.genes.count == 1,
           "Did not find correct number of genes, expected 1 but found #{@basic_study.genes.count}"

    # manually unset an attribute for expression_file_info to simulate "legacy" data
    @basic_study_exp_file.expression_file_info.modality = nil
    @basic_study_exp_file.save(validate: false)
    @basic_study_exp_file.reload
    assert_nil @basic_study_exp_file.expression_file_info.modality,
               "Did not unset value for modality: #{@basic_study_exp_file.expression_file_info.modality}"

    # run DeleteQueueJob and ensure proper deletion
    DeleteQueueJob.new(@basic_study_exp_file).perform
    @basic_study_exp_file.reload
    @basic_study.reload

    assert @basic_study_exp_file.queued_for_deletion,
           "Did not successfully queue exp matrix for deletion: #{@basic_study_exp_file.queued_for_deletion}"

    assert_equal @basic_study.genes.count, 0, "Should not have found any genes but found #{@basic_study.genes.count}"
  end

  test 'should allow reuse of filename after deletion' do
    filename = 'exp_matrix.txt'
    matrix = FactoryBot.create(:study_file, name: filename, file_type: 'Expression Matrix', study: @basic_study)
    assert matrix.persisted?
    assert matrix.valid?
    # queue for deletion and attempt to use same filename again
    DeleteQueueJob.new(matrix).perform
    matrix.reload
    assert matrix.queued_for_deletion
    assert_not_equal filename, matrix.upload_file_name
    new_matrix = FactoryBot.create(:study_file, name: filename, file_type: 'Expression Matrix', study: @basic_study)
    assert new_matrix.persisted?
    assert new_matrix.valid?
  end

  test 'should destroy differential expression results on file deletion' do
    study = FactoryBot.create(:study,
                              name_prefix: 'DiffExp DeleteQueueJon Test',
                              user: @user,
                              test_array: @@studies_to_clean)
    cells = %w[A B C D E F G]
    coordinates = 1.upto(7).to_a
    species = %w[dog cat dog dog cat cat cat]
    diseases = %w[measles measles measles none none measles measles]
    categories = %w[foo foo bar bar bar bar bar foo]
    organs = %w[brain brain heart brain heart heart brain]
    raw_matrix = FactoryBot.create(:expression_file,
                                   name: 'raw.txt',
                                   study: study,
                                   expression_file_info: {
                                     is_raw_counts: true,
                                     units: 'raw counts',
                                     library_preparation_protocol: 'Drop-seq',
                                     biosample_input_type: 'Whole cell',
                                     modality: 'Proteomic'
                                   })

    data_array_params = {
      name: 'raw.txt Cells', array_type: 'cells', linear_data_type: 'Study', study_id: study.id,
      cluster_name: 'raw.txt', array_index: 0, linear_data_id: study.id, study_file_id: raw_matrix.id,
      cluster_group_id: nil, subsample_annotation: nil, subsample_threshold: nil, values: cells
    }
    DataArray.create(data_array_params)

    cluster_file_1 = FactoryBot.create(:cluster_file,
                                       name: 'cluster_diffexp_1.txt',
                                       study: study,
                                       cell_input: {
                                         x: coordinates,
                                         y: coordinates,
                                         cells: cells
                                       },
                                       annotation_input: [
                                         { name: 'species', type: 'group', values: species }
                                       ])

    cluster_file_2 = FactoryBot.create(:cluster_file,
                                       name: 'cluster_diffexp_2.txt',
                                       study: study,
                                       cell_input: {
                                         x: coordinates,
                                         y: coordinates,
                                         cells: cells
                                       },
                                       annotation_input: [
                                         { name: 'disease', type: 'group', values: diseases }
                                       ])

    cluster_1 = ClusterGroup.find_by(study: study, study_file: cluster_file_1)
    cluster_2 = ClusterGroup.find_by(study: study, study_file: cluster_file_2)

    metadata_file = FactoryBot.create(:metadata_file,
                                      name: 'metadata.txt',
                                      cell_input: cells,
                                      study: study,
                                      annotation_input: [
                                        { name: 'category', type: 'group', values: categories },
                                        { name: 'organ', type: 'group', values: organs }
                                      ])

    DifferentialExpressionResult.create(
      study: study, cluster_group: cluster_1, annotation_name: 'species',
      annotation_scope: 'cluster', matrix_file_id: raw_matrix.id
    )
    DifferentialExpressionResult.create(
      study: study, cluster_group: cluster_2, annotation_name: 'disease',
      annotation_scope: 'cluster', matrix_file_id: raw_matrix.id
    )
    DifferentialExpressionResult.create(
      study: study, cluster_group: cluster_1, annotation_name: 'category',
      annotation_scope: 'study', matrix_file_id: raw_matrix.id
    )
    DifferentialExpressionResult.create(
      study: study, cluster_group: cluster_2, annotation_name: 'organ',
      annotation_scope: 'study', matrix_file_id: raw_matrix.id
    )

    mock = Minitest::Mock.new
    8.times do
      file_mock = Minitest::Mock.new
      file_mock.expect :present?, true
      file_mock.expect :delete, true
      mock.expect :get_workspace_file, file_mock, [study.bucket_id, String]
    end

    ApplicationController.stub :firecloud_client, mock do
      # test deletion of cluster file
      DeleteQueueJob.new(cluster_file_1).perform
      assert_not DifferentialExpressionResult.where(study: study, cluster_group: cluster_1).any?
      assert DifferentialExpressionResult.where(study: study, cluster_group: cluster_2).any?

      # test deletion of metadata file
      DeleteQueueJob.new(metadata_file).perform
      assert_not DifferentialExpressionResult.where(study: study, annotation_scope: 'study').any?

      # test deletion of matrix file
      DeleteQueueJob.new(raw_matrix).perform
      assert_not DifferentialExpressionResult.where(study: study).any?

      # assert all delete calls have been made, should be 8 total
      mock.verify
    end
  end

  test 'should delete parsed data from AnnData files' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'AnnData Delete Test',
                              user: @user,
                              test_array: @@studies_to_clean)
    study_file = FactoryBot.create(:ann_data_file,
                                   name: 'data.h5ad',
                                   study:,
                                   cell_input: %w[A B C D],
                                   annotation_input: [
                                     { name: 'disease', type: 'group', values: %w[cancer cancer normal normal] }
                                   ],
                                   coordinate_input: [
                                     { x_tsne: { x: [1, 2, 3, 4], y: [5, 6, 7, 8] } }
                                   ])
    study.update(default_options: { cluster: 'x_tsne', annotation: 'disease--group--study' })
    study.reload
    assert_equal 1, study.cluster_groups.size
    assert_equal 1, study.cell_metadata.size
    assert_equal %w[A B C D], study.all_cells_array
    assert_equal study_file, study.metadata_file
    assert_equal 'x_tsne', study.default_cluster.name
    mock = Minitest::Mock.new
    mock.expect(:get_workspace_files, [], [String, Hash])
    ApplicationController.stub :firecloud_client, mock do
      DeleteQueueJob.new(study_file).perform
      study.reload
      assert_equal 0, study.cluster_groups.size
      assert_equal 0, study.cell_metadata.size
      assert_empty study.all_cells_array
      assert_nil study.metadata_file
      assert_nil study.default_cluster
    end
  end
end
