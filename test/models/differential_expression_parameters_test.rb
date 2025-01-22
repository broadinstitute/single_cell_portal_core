require 'test_helper'

class DifferentialExpressionParametersTest < ActiveSupport::TestCase

  before(:all) do
    @dense_options = {
      annotation_name: 'Category',
      annotation_scope: 'cluster',
      annotation_file: 'gs://test_bucket/metadata.tsv',
      cluster_file: 'gs://test_bucket/cluster.tsv',
      cluster_name: 'UMAP',
      matrix_file_path: 'gs://test_bucket/dense.tsv',
      matrix_file_type: 'dense'
    }

    @sparse_options = {
      annotation_name: 'Category',
      annotation_scope: 'cluster',
      annotation_file: 'gs://test_bucket/metadata.tsv',
      cluster_file: 'gs://test_bucket/cluster.tsv',
      cluster_name: 'UMAP',
      matrix_file_path: 'gs://test_bucket/sparse.tsv',
      matrix_file_type: 'mtx',
      gene_file: 'gs://test_bucket/genes.tsv',
      barcode_file: 'gs://test_bucket/barcodes.tsv'
    }

    @anndata_options = {
      annotation_name: 'Category',
      annotation_scope: 'cluster',
      annotation_file: 'gs://test_bucket/metadata.tsv',
      cluster_file: 'gs://test_bucket/cluster.tsv',
      cluster_name: 'UMAP',
      matrix_file_path: 'gs://test_bucket/matrix.h5ad',
      matrix_file_type: 'h5ad',
      file_size: 10.gigabytes
    }

    @pairwise_options = {
      annotation_name: 'Category',
      annotation_scope: 'cluster',
      de_type: 'pairwise',
      group1: 'foo',
      group2: 'bar',
      annotation_file: 'gs://test_bucket/metadata.tsv',
      cluster_file: 'gs://test_bucket/cluster.tsv',
      cluster_name: 'UMAP',
      matrix_file_path: 'gs://test_bucket/dense.tsv',
      matrix_file_type: 'dense'
    }
  end

  test 'should instantiate and validate parameters' do
    dense_params = DifferentialExpressionParameters.new(@dense_options)
    assert dense_params.valid?
    sparse_params = DifferentialExpressionParameters.new(@sparse_options)
    assert sparse_params.valid?
    anndata_params = DifferentialExpressionParameters.new(@anndata_options)
    assert anndata_params.valid?
    pairwise_params = DifferentialExpressionParameters.new(@pairwise_options)
    assert pairwise_params.valid?

    # test conditional validations
    dense_params.annotation_file = ''
    dense_params.annotation_scope = 'foo'
    dense_params.matrix_file_type = 'bar'
    assert_not dense_params.valid?
    assert_equal %i[annotation_file annotation_scope matrix_file_type],
                 dense_params.errors.attribute_names.sort
    sparse_params.gene_file = 'foo'
    sparse_params.machine_type = 'foo'
    assert_not sparse_params.valid?
    assert_equal [:machine_type, :gene_file], sparse_params.errors.attribute_names
    pairwise_params.group1 = ''
    assert_not pairwise_params.valid?
  end

  test 'should format differential expression parameters for python cli' do
    dense_params = DifferentialExpressionParameters.new(@dense_options)
    options_array = dense_params.to_options_array
    dense_params.attributes.each do |name, value|
      next if value.blank? # some values will not be set

      expected_name = Parameterizable.to_cli_opt(name)
      assert_includes options_array, expected_name
      assert_includes options_array, value
    end
    assert_includes options_array, DifferentialExpressionParameters::PARAMETER_NAME

    sparse_params = DifferentialExpressionParameters.new(@sparse_options)
    options_array = sparse_params.to_options_array
    sparse_params.attributes.each do |name, value|
      next if value.blank?

      expected_name = Parameterizable.to_cli_opt(name)
      assert_includes options_array, expected_name
      assert_includes options_array, value
    end
    assert_includes options_array, DifferentialExpressionParameters::PARAMETER_NAME

    anndata_params = DifferentialExpressionParameters.new(@anndata_options)
    options_array = anndata_params.to_options_array
    anndata_params.attributes.each do |name, value|
      next if value.blank?

      expected_name = Parameterizable.to_cli_opt(name)
      assert_includes options_array, expected_name
      assert_includes options_array, value
    end
    assert_includes options_array, DifferentialExpressionParameters::PARAMETER_NAME

    pairwise_params = DifferentialExpressionParameters.new(@pairwise_options)
    options_array = pairwise_params.to_options_array
    pairwise_params.attributes.each do |name, value|
      next if value.blank?

      expected_name = Parameterizable.to_cli_opt(name)
      assert_includes options_array, expected_name
      assert_includes options_array, value
    end
    assert_includes options_array, DifferentialExpressionParameters::PARAMETER_NAME
  end

  test 'converts keys into cli options' do
    assert_equal '--annotation-name', Parameterizable.to_cli_opt(:annotation_name)
    assert_equal '--foo', Parameterizable.to_cli_opt('foo')
  end

  test 'should set default machine type for DE jobs' do
    params = DifferentialExpressionParameters.new
    assert_equal 'n2d-highmem-8', params.default_machine_type
    assert_equal 'n2d-highmem-8', params.machine_type
  end

  test 'should scale machine type for h5ad files up to limit' do
    params = DifferentialExpressionParameters.new(
      matrix_file_path: 'gs://test_bucket/matrix.h5ad', matrix_file_type: 'h5ad', file_size: 32.gigabytes
    )
    assert_equal 'n2d-highmem-16', params.machine_type
    assert_nil params.next_machine_type
  end

  test 'should remove non-attribute values from attribute hash' do
    dense_params = DifferentialExpressionParameters.new(@dense_options)
    assert_not_includes dense_params.attributes, :machine_type
  end
end
