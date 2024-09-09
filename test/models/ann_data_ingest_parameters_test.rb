require 'test_helper'

class AnnDataIngestParametersTest < ActiveSupport::TestCase

  before(:all) do
    @extract_params = {
      anndata_file: 'gs://bucket_id/test.h5ad',
      file_size: 50.gigabytes
    }

    @file_id = BSON::ObjectId.new
    @accession = 'SCP1234'
    @fragment_basepath = "gs://bucket_id/_scp_internal/anndata_ingest/#{@accession}_#{@file_id}"

    @cluster_filename = 'h5ad_frag.cluster.X_umap.tsv.gz'
    @ingest_cluster_params = {
      ingest_anndata: false,
      extract: nil,
      obsm_keys: nil,
      ingest_cluster: true,
      cluster_file: "#{@fragment_basepath}/#{@cluster_filename}",
      name: 'X_umap',
      domain_ranges: '{}'
    }

    @metadata_filename = 'h5ad_frag.metadata.tsv.gz'
    @ingest_metadata_params = {
      ingest_anndata: false,
      extract: nil,
      obsm_keys: nil,
      cell_metadata_file: "#{@fragment_basepath}/#{@metadata_filename}",
      ingest_cell_metadata: true
    }
    @matrix_filename = 'h5ad_frag.matrix.processed.tsv.gz'
    @features_filename = 'h5ad_frag.features.processed.tsv.gz'
    @barcodes_filename = 'h5ad_frag.barcodes.processed.tsv.gz'
    @ingest_expression_params = {
      ingest_anndata: false,
      extract: nil,
      obsm_keys: nil,
      matrix_file: "#{@fragment_basepath}/#{@matrix_filename}",
      matrix_file_type: 'mtx',
      gene_file: "#{@fragment_basepath}/#{@features_filename}",
      barcode_file: "#{@fragment_basepath}/#{@barcodes_filename}"
    }
  end

  test 'should validate extract params' do
    extraction = AnnDataIngestParameters.new(@extract_params)
    assert extraction.valid?
    %i[ingest_anndata].each do |attr|
      assert_equal true, extraction.send(attr)
    end
    %i[ingest_cluster cluster_file name domain_ranges ingest_cell_metadata cell_metadata_file].each do |attr|
      assert extraction.send(attr).blank?
    end

    cmd = '--ingest-anndata --anndata-file gs://bucket_id/test.h5ad --obsm-keys ["X_umap", "X_tsne"] --extract ' \
          '["cluster", "metadata", "processed_expression", "raw_counts"]'
    assert_equal cmd, extraction.to_options_array.join(' ')
    assert_equal 'n2d-highmem-32', extraction.machine_type
  end

  test 'should validate cluster params' do
    cluster_ingest = AnnDataIngestParameters.new(@ingest_cluster_params)
    assert cluster_ingest.valid?
    assert_equal true, cluster_ingest.ingest_cluster
    %i[ingest_anndata extract anndata_file obsm_keys].each do |attr|
      assert cluster_ingest.send(attr).blank?
    end
    cluster_cmd = "--ingest-cluster --cluster-file #{@fragment_basepath}/" \
                  'h5ad_frag.cluster.X_umap.tsv.gz --name X_umap --domain-ranges {}'
    assert_equal cluster_cmd, cluster_ingest.to_options_array.join(' ')
    assert_equal cluster_ingest.default_machine_type, cluster_ingest.machine_type
  end

  test 'should validate metadata params' do
    metadata_ingest = AnnDataIngestParameters.new(@ingest_metadata_params)
    assert metadata_ingest.valid?
    assert_equal true, metadata_ingest.ingest_cell_metadata
    %i[ingest_anndata extract anndata_file].each do |attr|
      assert metadata_ingest.send(attr).blank?
    end
    md_cmd = "--cell-metadata-file #{@fragment_basepath}/h5ad_frag.metadata.tsv.gz --ingest-cell-metadata"
    assert_equal md_cmd, metadata_ingest.to_options_array.join(' ')
    assert_equal metadata_ingest.default_machine_type, metadata_ingest.machine_type
  end

  test 'should validate expression params' do
    exp_ingest = AnnDataIngestParameters.new(@ingest_expression_params)
    assert exp_ingest.valid?
    %i[ingest_anndata extract anndata_file].each do |attr|
      assert exp_ingest.send(attr).blank?
    end
    exp_cmd = "--matrix-file #{@fragment_basepath}/h5ad_frag.matrix.processed.tsv.gz --matrix-file-type mtx " \
              "--gene-file #{@fragment_basepath}/h5ad_frag.features.processed.tsv.gz " \
              "--barcode-file #{@fragment_basepath}/h5ad_frag.barcodes.processed.tsv.gz"
    assert_equal exp_cmd, exp_ingest.to_options_array.join(' ')
    assert_equal exp_ingest.default_machine_type, exp_ingest.machine_type
  end

  test 'should set default machine type and allow override' do
    params = AnnDataIngestParameters.new(@extract_params)
    assert_equal 'n2d-highmem-32', params.machine_type
    new_machine = 'n2d-highmem-80'
    params.machine_type = new_machine
    assert_equal new_machine, params.machine_type
    assert params.valid?
    params.machine_type = 'foo'
    assert_not params.valid?
  end

  test 'should set default machine type' do
    params = AnnDataIngestParameters.new
    assert_equal 'n2d-highmem-4', params.default_machine_type
    assert_equal 'n2d-highmem-4', params.machine_type
  end
end
