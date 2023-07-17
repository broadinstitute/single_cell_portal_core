require 'test_helper'

class AnnDataIngestParametersTest < ActiveSupport::TestCase

  before(:all) do
    @extract_params = {
      anndata_file: 'gs://bucket_id/test.h5ad',
    }

    @file_id = BSON::ObjectId.new
    @accession = 'SCP1234'
    @cluster_filename = 'h5ad_frag.cluster.X_umap.tsv.gz'
    @ingest_cluster_params = {
      ingest_anndata: false,
      extract: nil,
      obsm_keys: nil,
      ingest_cluster: true,
      cluster_file: "gs://bucket_id/_scp_internal/anndata_ingest/#{@accession}_#{@file_id}/#{@cluster_filename}",
      name: 'X_umap',
      domain_ranges: '{}'
    }

    @metadata_filename = 'h5ad_frag.metadata.tsv.gz'
    @ingest_metadata_params = {
      ingest_anndata: false,
      extract: nil,
      obsm_keys: nil,
      cell_metadata_file: "gs://bucket_id/_scp_internal/anndata_ingest/#{@accession}_#{@file_id}/#{@metadata_filename}",
      ingest_cell_metadata: true
    }
    @matrix_filename = 'h5ad_frag.matrix.processed.tsv.gz'
    @features_filename = 'h5ad_frag.metadata.tsv.gz'
    @barcodes_filename = 'h5ad_frag.metadata.tsv.gz'
    @ingest_expression_params = {
      ingest_anndata: false,
      extract: nil,
      obsm_keys: nil,
      cell_metadata_file: "gs://bucket_id/_scp_internal/anndata_ingest/#{@accession}_#{@file_id}/#{@metadata_filename}",
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

    cmd = '--ingest-anndata --anndata-file gs://bucket_id/test.h5ad --obsm-keys ["X_umap", "X_tsne"] --extract ' \
          '["cluster", "metadata", "processed_expression"]'
    assert_equal cmd, extraction.to_options_array.join(' ')

    cluster_ingest = AnnDataIngestParameters.new(@ingest_cluster_params)
    assert cluster_ingest.valid?
    assert_equal true, cluster_ingest.ingest_cluster
    %i[ingest_anndata extract anndata_file obsm_keys].each do |attr|
      assert cluster_ingest.send(attr).blank?
    end
    identifier = "#{@accession}_#{@file_id}"
    cluster_cmd = '--ingest-cluster --cluster-file gs://bucket_id/_scp_internal/anndata_ingest/' \
                  "#{identifier}/h5ad_frag.cluster.X_umap.tsv.gz --name X_umap --domain-ranges {}"
    assert_equal cluster_cmd, cluster_ingest.to_options_array.join(' ')

    metadata_ingest = AnnDataIngestParameters.new(@ingest_metadata_params)
    assert metadata_ingest.valid?
    assert_equal true, metadata_ingest.ingest_cell_metadata
    %i[ingest_anndata extract anndata_file].each do |attr|
      assert metadata_ingest.send(attr).blank?
    end
    md_cmd = "--cell-metadata-file gs://bucket_id/_scp_internal/anndata_ingest/#{identifier}/" \
             'h5ad_frag.metadata.tsv.gz --ingest-cell-metadata'
    assert_equal md_cmd, metadata_ingest.to_options_array.join(' ')
  end
end
