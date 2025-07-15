require 'test_helper'

class DotPlotGeneIngestParametersTest < ActiveSupport::TestCase
  before(:all) do
    cluster_group_id = BSON::ObjectId.new
    @dense_options = {
      cell_metadata_file: 'gs://test_bucket/metadata.tsv',
      cluster_file: 'gs://test_bucket/cluster.tsv',
      cluster_group_id:,
      matrix_file_path: 'gs://test_bucket/dense.tsv',
      matrix_file_type: 'dense',
    }

    @sparse_options = {
      cell_metadata_file: 'gs://test_bucket/metadata.tsv',
      cluster_file: 'gs://test_bucket/cluster.tsv',
      cluster_group_id:,
      matrix_file_path: 'gs://test_bucket/sparse.tsv',
      matrix_file_type: 'mtx',
      gene_file: 'gs://test_bucket/genes.tsv',
      barcode_file: 'gs://test_bucket/barcodes.tsv'
    }

    @anndata_options = {
      cell_metadata_file: 'gs://test_bucket/metadata.tsv',
      cluster_file: 'gs://test_bucket/cluster.tsv',
      cluster_group_id:,
      matrix_file_path: 'gs://test_bucket/matrix.h5ad',
      matrix_file_type: 'mtx',
      gene_file: 'gs://test_bucket/genes.tsv',
      barcode_file: 'gs://test_bucket/barcodes.tsv'
    }
  end

  test 'should create and validate parameters' do
    [@dense_options, @sparse_options, @anndata_options].each do |options|
      params = DotPlotGeneIngestParameters.new(**options)
      assert params.valid?
      assert_equal DotPlotGeneIngestParameters::PARAM_DEFAULTS[:machine_type], params.machine_type
      if options[:matrix_file_type] == 'mtx'
        assert params.gene_file.present?
        assert params.barcode_file.present?
      else
        assert params.gene_file.nil?
        assert params.barcode_file.nil?
      end
    end
  end

  test 'should find associated cluster group' do
    user = FactoryBot.create(:user, test_array: @@users_to_clean)
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'DotPlotGeneIngestParameters Test',
                              user:,
                              test_array: @@studies_to_clean)
    FactoryBot.create(:cluster_file,
                      name: 'cluster.txt',
                      study:,
                      cell_input: { x: [1, 4, 6], y: [7, 5, 3], cells: %w[A B C] }
    )
    cluster_group = ClusterGroup.find_by(study:)
    new_options = @dense_options.dup.merge(cluster_group_id: cluster_group.id)
    params = DotPlotGeneIngestParameters.new(**new_options)
    assert_equal cluster_group, params.cluster_group
  end
end
