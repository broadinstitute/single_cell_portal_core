require 'test_helper'

class StudyFileTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Study File Test',
                               user: @user,
                               test_array: @@studies_to_clean)

    @expression_matrix = FactoryBot.create(:study_file, name: 'dense.txt', file_type: 'Expression Matrix', study: @study)

    @expression_matrix.build_expression_file_info(is_raw_counts: true, units: 'raw counts',
                                                  library_preparation_protocol: 'MARS-seq',
                                                  modality: 'Transcriptomic: unbiased',
                                                  biosample_input_type: 'Whole cell')
    @expression_matrix.parse_status = 'parsed'
    @expression_matrix.save!

    @metadata_file = FactoryBot.create(:study_file,
                                       name: 'metadata.tsv',
                                       file_type: 'Metadata',
                                       use_metadata_convention: true,
                                       study: @study)
    @metadata_file.update(parse_status: 'parsing')
    @cluster_file = FactoryBot.create(:cluster_file,
                                      name: 'cluster.txt', study: @study,
                                      cell_input: {
                                        x: [1, 4, 6],
                                        y: [7, 5, 3],
                                        z: [2, 8, 9],
                                        cells: %w[A B C]
                                      },
                                      x_axis_label: 'PCA 1',
                                      y_axis_label: 'PCA 2',
                                      z_axis_label: 'PCA 3',
                                      cluster_type: '3d',
                                      annotation_input: [
                                        { name: 'Category', type: 'group', values: %w[bar bar baz] },
                                        { name: 'Intensity', type: 'numeric', values: [1.1, 2.2, 3.3] }
                                      ])
    @cluster_file.update(parse_status: 'parsing')
    @cluster = @study.cluster_groups.first
    @cluster.update(is_subsampling: true)
  end

  teardown do
    feature_flags = FeatureFlag.where(:name.in => %w[raw_counts_required_backend convention_required])
    feature_flags.update_all(default_value: false)
    FeatureFlagOption.destroy_all
  end

  test 'should prevent deletion of study files during parsing or subsampling' do
    # expression matrix is parsed, so it should be deletable
    assert @expression_matrix.can_delete_safely?,
           'Did not correctly return true for a parsed expression matrix'

    # cluster/metadata files should not be deletable yet as they are parsing
    assert_not @metadata_file.can_delete_safely?,
           'Metadata file is still parsing and should not be deletable'
    assert_not @cluster_file.can_delete_safely?,
           'Metadata file is still parsing and should not be deletable'

    # once parsing completes, because the cluster is subsampling, they should still not be deletable
    @study.study_files.where(:file_type.in => %w(Cluster Metadata)).update_all(parse_status: 'parsed')
    assert_not @metadata_file.can_delete_safely?,
           'Metadata file is still subsampling and should not be deletable'
    assert_not @cluster_file.can_delete_safely?,
           'Metadata file is still subsampling and should not be deletable'

    # once cluster is subsampled, both files should be deletable
    @cluster.update(subsampled: true, is_subsampling: false)
    # need to call reload to refresh cached object
    @metadata_file.reload
    @cluster_file.reload
    assert @metadata_file.can_delete_safely?,
           'Metadata file is no longer parsing/subsampling and should be deletable'
    assert @cluster_file.can_delete_safely?,
           'Metadata file is no longer parsing/subsampling and should be deletable'
  end

  test 'expression file data validates' do
    # note that we don't (and shouldn't) actually *save* anything in this test,
    # so we use throwaway objects and ids.

    invalid_study_file = StudyFile.new(
      study: Study.new,
      file_type: 'Expression Matrix',
      name: 'test_exp_validate',
      taxon_id: Taxon.new.id,
      expression_file_info: ExpressionFileInfo.new(
        units: 'bad_value',
        library_preparation_protocol: 'Mars-seq', # Incorrect case
        is_raw_counts: true
      )
    )
    assert_equal false, invalid_study_file.valid?
    expected_errors = {
      base: [
        'Units is not included in the list, ' \
        'Library preparation protocol is not included in the list'
      ]
    }
    # Modality and Library preparation protocol will be populated with default values if undefined
    assert_equal(expected_errors, invalid_study_file.errors.messages)

    valid_study_file = StudyFile.new(
      study: Study.new,
      file_type: 'Expression Matrix',
      name: 'test_exp_validate',
      taxon_id: Taxon.new.id,
      expression_file_info: ExpressionFileInfo.new(
        units: 'raw counts',
        library_preparation_protocol: 'MARS-seq',
        biosample_input_type: 'Whole cell',
        modality: 'Transcriptomic: targeted',
        is_raw_counts: true
      )
    )
    assert_equal true, valid_study_file.valid?
  end

  test 'should enforce raw counts associations' do
    raw_counts_required = FeatureFlag.find_or_create_by(name: 'raw_counts_required_backend')
    raw_counts_required.update(default_value: true)
    matrix = FactoryBot.create(:study_file, name: 'dense_2.txt', file_type: 'Expression Matrix', study: @study)
    matrix.build_expression_file_info(is_raw_counts: false, library_preparation_protocol: 'MARS-seq',
                                      modality: 'Transcriptomic: unbiased', biosample_input_type: 'Whole cell')
    assert_not matrix.valid?
    matrix.expression_file_info.raw_counts_associations = [@expression_matrix.id.to_s]
    assert matrix.valid?

    # test exemption functionality
    matrix.expression_file_info.raw_counts_associations = []
    assert_not matrix.valid?
    study_user = @study.user
    study_user.set_flag_option('raw_counts_required_backend', false)
    assert matrix.valid?
    # test study-based exemption
    study_user.remove_flag_option('raw_counts_required_backend')
    assert_not matrix.valid?
    @study.set_flag_option('raw_counts_required_backend', false)
    assert matrix.valid?
  end

  test 'should enforce metadata convention' do
    convention_required = FeatureFlag.find_or_create_by(name: 'convention_required')
    convention_required.update(default_value: true)
    @metadata_file.use_metadata_convention = false
    assert_not @metadata_file.valid?
    study_user = @study.user
    study_user.set_flag_option('convention_required', false)
    assert @metadata_file.valid?
    # test study-based exemption
    study_user.remove_flag_option('convention_required')
    assert_not @metadata_file.valid?
    @study.set_flag_option('convention_required', false)
    assert @metadata_file.valid?
  end

  test 'should find associated raw/processed matrix files' do
    matrix = FactoryBot.create(:study_file, name: 'matrix.txt', file_type: 'Expression Matrix', study: @study)
    matrix.build_expression_file_info(is_raw_counts: false, library_preparation_protocol: 'MARS-seq',
                                      modality: 'Transcriptomic: unbiased', biosample_input_type: 'Whole cell',
                                      raw_counts_associations: [@expression_matrix.id.to_s])
    matrix.save!
    associated_raw_files = matrix.associated_matrix_files(:raw)
    assert_equal @expression_matrix, associated_raw_files.first
    associated_processed_files = @expression_matrix.associated_matrix_files(:processed)
    assert_equal matrix, associated_processed_files.first
  end

  test 'can find AnnData files using getters' do
    ann_data_study = FactoryBot.create(:detached_study,
                                       name_prefix: 'AnnData File Test',
                                       user: @user,
                                       test_array: @@studies_to_clean)
    ann_data_file = FactoryBot.create(:ann_data_file, name: 'test.h5ad', study: ann_data_study)
    assert_not ann_data_study.clustering_files.include? ann_data_file
    assert_not ann_data_study.expression_matrices.include? ann_data_file
    assert_nil ann_data_study.metadata_file
    assert_not ann_data_file.is_expression?
    assert_not ann_data_file.is_raw_counts_file?

    # test flags
    ann_data_file.ann_data_file_info.update(
      has_clusters: true, has_expression: true, has_raw_counts: true, has_metadata: true
    )
    assert_includes ann_data_study.expression_matrices, ann_data_file
    assert_includes ann_data_study.clustering_files, ann_data_file
    assert_equal ann_data_study.metadata_file, ann_data_file
    assert ann_data_file.is_expression?
    assert ann_data_file.is_raw_counts_file?
  end

  test 'should determine if file is/can be gzipped' do
    bam_path = Rails.root.join("test/test_data/fixed_neurons_6days_2000_possorted_genome_bam_test_data.bam")
    bam_file = StudyFile.create!(
      study: @study,
      upload: File.open(bam_path),
      file_type: 'BAM',
      name: 'fixed_neurons_6days_2000_possorted_genome_bam_test_data.bam'
    )
    assert bam_file.gzipped?
    assert_not bam_file.can_gzip?
    cluster_path = Rails.root.join('test/test_data/cluster_example.txt')
    cluster_file = StudyFile.create!(
      study: @study,
      upload: File.open(cluster_path),
      file_type: 'Cluster',
      name: 'cluster_example.txt'
    )
    assert_not cluster_file.gzipped?
    assert cluster_file.can_gzip?
  end
end
