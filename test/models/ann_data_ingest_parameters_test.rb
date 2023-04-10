require 'test_helper'

class AnnDataIngestParametersTest < ActiveSupport::TestCase

  before(:all) do
    @extract_params = {
      anndata_file: 'gs://test_bucket/test.h5ad',
    }

    @ingest_cluster_params = {
      ingest_anndata: false,
      extract: nil,
      obsm_keys: nil,
      ingest_cluster: true,
      cluster_file: 'gs://test_bucket/_scp_internal/anndata_ingest/h5ad_file_id/h5ad_frag.cluster.X_umap.tsv',
      name: 'X_umap',
      domain_ranges: '{}'
    }

    @ingest_metadata_params = {
      ingest_anndata: false,
      extract: nil,
      obsm_keys: nil,
      cell_metadata_file: 'gs://test_bucket/_scp_internal/anndata_ingest/h5ad_file_id/h5ad_frag.metadata.tsv',
      ingest_cell_metadata: true
    }
  end

  test 'should instantiate and validate params' do
    extraction = AnnDataIngestParameters.new(@extract_params)
    assert extraction.valid?
    %i[ingest_anndata].each do |attr|
      assert_equal true, extraction.send(attr)
    end
    %i[ingest_cluster cluster_file name domain_ranges ingest_cell_metadata cell_metadata_file].each do |attr|
      assert extraction.send(attr).blank?
    end

    cmd = '--ingest-anndata --anndata-file gs://test_bucket/test.h5ad --extract ["cluster", "metadata"] ' \
          '--obsm-keys ["X_umap", "X_tsne"]'
    assert_equal cmd, extraction.to_options_array.join(' ')

    cluster_ingest = AnnDataIngestParameters.new(@ingest_cluster_params)
    assert cluster_ingest.valid?
    assert_equal true, cluster_ingest.ingest_cluster
    %i[ingest_anndata extract anndata_file obsm_keys].each do |attr|
      assert cluster_ingest.send(attr).blank?
    end
    cluster_cmd = '--ingest-cluster --cluster-file gs://test_bucket/_scp_internal/anndata_ingest/' \
                  'h5ad_file_id/h5ad_frag.cluster.X_umap.tsv --name X_umap --domain-ranges {}'
    assert_equal cluster_cmd, cluster_ingest.to_options_array.join(' ')


    metadata_ingest = AnnDataIngestParameters.new(@ingest_metadata_params)
    assert metadata_ingest.valid?
    assert_equal true, metadata_ingest.ingest_cell_metadata
    %i[ingest_anndata extract anndata_file].each do |attr|
      assert metadata_ingest.send(attr).blank?
    end
    metadata_cmd = '--cell-metadata-file gs://test_bucket/_scp_internal/anndata_ingest/h5ad_file_id/h5ad_frag.metadata.tsv --ingest-cell-metadata'
    assert_equal metadata_cmd, metadata_ingest.to_options_array.join(' ')

  end

  test 'should set fragment filename for extracted files' do
    extraction = AnnDataIngestParameters.new(@extract_params)
    %w[X_umap X_tsne].each do |fragment|
      assert_equal "gs://test_bucket/_scp_internal/anndata_ingest/h5ad_file_id/h5ad_frag.cluster.#{fragment}.tsv",
                   extraction.fragment_file_gs_url('test_bucket', 'cluster', 'h5ad_file_id', fragment)
    end
  end
end
