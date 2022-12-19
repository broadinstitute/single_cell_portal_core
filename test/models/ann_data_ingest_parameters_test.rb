require 'test_helper'

class AnnDataIngestParametersTest < ActiveSupport::TestCase

  before(:all) do
    @extract_params = {
      anndata_file: 'gs://test_bucket/test.h5ad',
    }

    @ingest_cluster_params = {
      ingest_anndata: false,
      extract_cluster: false,
      obsm_keys: nil,
      ingest_cluster: true,
      cluster_file: 'gs://test_bucket/_scp_internal/anndata_ingest/X_umap.cluster.anndata_segment.tsv',
      name: 'X_umap',
      domain_ranges: '{}'
    }
  end

  test 'should instantiate and validate params' do
    extraction = AnnDataIngestParameters.new(@extract_params)
    assert extraction.valid?
    %i[ingest_anndata extract_cluster].each do |attr|
      assert_equal true, extraction.send(attr)
    end
    %i[ingest_cluster cluster_file name domain_ranges].each do |attr|
      assert extraction.send(attr).blank?
    end
    cmd = "--ingest-anndata --anndata-file gs://test_bucket/test.h5ad --extract-cluster --obsm-keys ['X_umap','X_tsne']"
    assert_equal cmd, extraction.to_options_array.join(' ')
    cluster_ingest = AnnDataIngestParameters.new(@ingest_cluster_params)
    assert cluster_ingest.valid?
    assert_equal true, cluster_ingest.ingest_cluster
    %i[ingest_anndata extract_cluster anndata_file obsm_keys].each do |attr|
      assert cluster_ingest.send(attr).blank?
    end
    cluster_cmd = '--ingest-cluster --cluster-file gs://test_bucket/_scp_internal/anndata_ingest/' \
                  'X_umap.cluster.anndata_segment.tsv --name X_umap --domain-ranges {}'
    assert_equal cluster_cmd, cluster_ingest.to_options_array.join(' ')
  end

  test 'should extract attribute as array' do
    extraction = AnnDataIngestParameters.new(@extract_params)
    assert_equal %w[X_umap X_tsne], extraction.attribute_as_array(:obsm_keys)
  end

  test 'should set fragment filename for extracted files' do
    extraction = AnnDataIngestParameters.new(@extract_params)
    %w[X_umap X_tsne].each do |fragment|
      assert_equal "gs://test/_scp_internal/anndata_ingest/#{fragment}.cluster.anndata_segment.tsv",
                   extraction.fragment_file_gs_url('test', 'cluster', fragment)
    end
  end
end
