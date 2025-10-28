require 'test_helper'

class DotPlotServiceTest < ActiveSupport::TestCase
  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'DotPlotService Test Study',
                               user: @user,
                               test_array: @@studies_to_clean)
    cells = %w[A B C]
    genes = %w[pten agpat2]
    expression_input = genes.index_with(cells.map { |c| [c, rand.floor(3)] })
    @cluster_file = FactoryBot.create(:cluster_file,
                                      name: 'cluster_example.txt',
                                      study: @study,
                                      cell_input: { x: cells, y: cells })
    @expression_file = FactoryBot.create(:expression_file,
                                         name: 'expression_example.txt',
                                         study: @study,
                                         expression_input:)
    @metadata_file = FactoryBot.create(:metadata_file,
                                       name: 'metadata.txt',
                                       study: @study,
                                       cell_input: cells,
                                       annotation_input: [
                                         { name: 'species', type: 'group', values: %w[dog cat dog] },
                                         { name: 'disease', type: 'group', values: %w[none none measles] }
                                       ])
    @cluster_group = @study.cluster_groups.first
  end

  teardown do
    DotPlotGene.delete_all
  end

  test 'should determine study eligibility for preprocessing' do
    assert DotPlotService.study_eligible?(@study)
    empty_study = FactoryBot.create(:detached_study,
                                    name_prefix: 'Empty DotPlot',
                                    user: @user,
                                    test_array: @@studies_to_clean)
    assert_not DotPlotService.study_eligible?(empty_study)
  end

  test 'should determine if cluster has been processed' do
    assert_not DotPlotService.cluster_processed?(@study, @cluster_group)
    DotPlotGene.create(
      study: @study,
      study_file: @expression_file,
      cluster_group: @cluster_group,
      gene_symbol: 'Pten',
      exp_scores: {}
    )
    assert DotPlotService.cluster_processed?(@study, @cluster_group)
  end

  test 'should get processed matrices for study' do
    assert_includes DotPlotService.study_processed_matrices(@study), @expression_file
    empty_study = FactoryBot.create(:detached_study,
                                    name_prefix: 'Empty DotPlot',
                                    user: @user,
                                    test_array: @@studies_to_clean)
    assert_empty DotPlotService.study_processed_matrices(empty_study)
  end

  test 'should validate study for dot plot preprocessing' do
    DotPlotService.validate_study(@study, @cluster_group) # should not raise error
    empty_study = FactoryBot.create(:detached_study,
                                    name_prefix: 'Empty DotPlot',
                                    user: @user,
                                    test_array: @@studies_to_clean)
    assert_raise ArgumentError do
      DotPlotService.validate_study(empty_study, ClusterGroup.new)
    end
  end

  test 'should get dense parameters for dot plot gene ingest job' do
    params = DotPlotService.create_params_object(@cluster_group, @expression_file, @metadata_file)
    assert_equal params.matrix_file_type, 'dense'
    assert_equal params.cell_metadata_file, @metadata_file.gs_url
    assert_equal params.cluster_file, @cluster_file.gs_url
    assert_equal params.matrix_file_path, @expression_file.gs_url
  end

  test 'should get sparse parameters for dot plot gene ingest job' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Sparse DotPlotService Test Study',
                              user: @user,
                              test_array: @@studies_to_clean)
    cluster_file = FactoryBot.create(:cluster_file,
                                     name: 'cluster_example_sparse.txt',
                                     study:,
                                     cell_input: { x: [1, 2, 3], y: [4, 5, 6] })
    metadata_file = FactoryBot.create(:metadata_file, name: 'metadata.txt', study:)
    matrix = FactoryBot.create(:expression_file,
                               name: 'matrix.mtx',
                               file_type: 'MM Coordinate Matrix',
                               study:)
    gene_file = FactoryBot.create(:study_file, name: 'genes.tsv', file_type: '10X Genes File', study:)
    barcode_file = FactoryBot.create(:study_file, name: 'barcodes.tsv', file_type: '10X Barcodes File', study:)
    bundle = StudyFileBundle.new(study:, bundle_type: matrix.file_type)
    bundle.add_files(matrix, gene_file, barcode_file)
    bundle.save!
    cluster_group = study.cluster_groups.first
    params = DotPlotService.create_params_object(cluster_group, matrix, metadata_file)
    assert_equal params.matrix_file_type, 'mtx'
    assert_equal params.cell_metadata_file, metadata_file.gs_url
    assert_equal params.cluster_file, cluster_file.gs_url
    assert_equal params.matrix_file_path, matrix.gs_url
  end

  test 'should get anndata parameters for dot plot gene ingest job' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'AnnData DotPlotService Test Study',
                              user: @user,
                              test_array: @@studies_to_clean)
    anndata_file = FactoryBot.create(:ann_data_file,
                                     name: 'matrix.h5ad',
                                     study:,
                                     cell_input: %w[A B C D],
                                     coordinate_input: [
                                       { umap: { x: [1, 2, 3, 4], y: [5, 6, 7, 8] } }
                                     ])
    cluster_group = study.cluster_groups.first
    params = DotPlotService.create_params_object(cluster_group, anndata_file, anndata_file)
    assert_equal 'mtx', params.matrix_file_type
    assert_equal RequestUtils.data_fragment_url(anndata_file, 'metadata'),
                 params.cell_metadata_file
    assert_equal RequestUtils.data_fragment_url(anndata_file, 'cluster', file_type_detail: 'X_umap'),
                 params.cluster_file
    assert_equal RequestUtils.data_fragment_url(anndata_file, 'matrix', file_type_detail: 'processed'),
                 params.matrix_file_path
    assert_equal RequestUtils.data_fragment_url(anndata_file, 'features', file_type_detail: 'processed'),
                 params.gene_file
    assert_equal RequestUtils.data_fragment_url(anndata_file, 'barcodes', file_type_detail: 'processed'),
                 params.barcode_file
  end

  test 'should run preprocess expression job' do
    job_mock = Minitest::Mock.new
    job_mock.expect(:push_remote_and_launch_ingest, Delayed::Job.new)
    mock = Minitest::Mock.new
    mock.expect(:delay, job_mock)
    IngestJob.stub :new, mock do
      assert DotPlotService.run_process_dot_plot_genes(@study, @cluster_group, @user)
    end
  end

  test 'should run preprocess job on all study data' do
    cells = %w[D E F]
    FactoryBot.create(:cluster_file,
                      name: 'cluster_2.txt',
                      study: @study,
                      cell_input: { x: cells, y: cells })
    job_mock = Minitest::Mock.new
    2.times { job_mock.expect(:push_remote_and_launch_ingest, Delayed::Job.new) }
    mock = Minitest::Mock.new
    2.times { mock.expect(:delay, job_mock) }
    IngestJob.stub :new, mock do
      DotPlotService.process_all_study_data(@study, @user)
      mock.verify
      job_mock.verify
    end
  end
end
