require 'test_helper'

class AnnDataFileInfoTest < ActiveSupport::TestCase
  def generate_id
    BSON::ObjectId.new.to_s
  end

  test 'should find matching fragments' do
    anndata_info = AnnDataFileInfo.new(
      data_fragments: [
        { _id: generate_id, data_type: :cluster, name: 'UMAP', obsm_key_name: 'X_umap' },
        { _id: generate_id, data_type: :cluster, name: 'tSNE', obsm_key_name: 'X_tsne' },
        { _id: generate_id, data_type: :expression, y_axis_title: 'log(TPM) expression' }
      ]
    )
    anndata_info.data_fragments.each do |fragment|
      assert_equal fragment, anndata_info.find_fragment(**fragment)
      # remove random key and assert we still get a match (result would still be unique)
      matcher = fragment.deep_dup
      matcher.delete(fragment.keys.sample)
      assert_equal fragment, anndata_info.find_fragment(**matcher)
    end
  end

  test 'should get cluster domain ranges from fragment' do
    anndata_info = AnnDataFileInfo.new(
      data_fragments: [
        {
          _id: generate_id, data_type: :cluster, name: 'UMAP', obsm_key_name: 'X_umap',
          x_axis_min: -10, x_axis_max: 10, y_axis_min: -15, y_axis_max: 15
        }
      ]
    )
    expected_range = { x_axis_min: -10.0, x_axis_max: 10.0, y_axis_min: -15.0, y_axis_max: 15.0 }
    assert_equal expected_range, anndata_info.get_cluster_domain_ranges('UMAP')
  end

  test 'should merge form data' do
    taxon_id = BSON::ObjectId.new.to_s
    form_params = {
      name: 'data.h5ad',
      description: 'anndata file description',
      extra_expression_form_info_attributes: {
        _id: generate_id,
        description: 'expression description',
        taxon_id:,
        y_axis_label: 'log(TPM) expression'
      },
      metadata_form_info_attributes: {
        use_metadata_convention: true
      },
      cluster_form_info_attributes: {
          _id: generate_id,
          name: 'UMAP',
          description: 'cluster description',
          obsm_key_name: 'X_umap',
          x_axis_label: 'x axis',
          y_axis_label: 'y axis',
          x_axis_min: '-10',
          x_axis_max: '10',
          y_axis_min: '-10',
          y_axis_max: '10'
      }
    }
    merged_data = AnnDataFileInfo.new.merge_form_data(form_params)
    assert_equal taxon_id, merged_data[:taxon_id]
    assert merged_data[:use_metadata_convention]
    root_form_key = :ann_data_file_info_attributes
    cluster_fragment = merged_data.dig(root_form_key, :data_fragments).detect { |f| f[:name] == 'UMAP' }
    assert cluster_fragment.present?
    assert_equal 'x axis', cluster_fragment[:x_axis_label]
    assert_equal '10', cluster_fragment[:x_axis_max]
    assert_equal 'cluster description', cluster_fragment[:description]
    expr_fragment = merged_data.dig(root_form_key, :data_fragments).detect { |f| f[:data_type] == :expression }
    assert_equal 'expression description', expr_fragment[:description]
    assert_equal 'log(TPM) expression', expr_fragment[:y_axis_label]
  end

  test 'should extract specified data fragment from form data' do
    taxon_id = BSON::ObjectId.new.to_s
    description = 'this is the description'
    form_segment = { description:, taxon_id:, other_data: 'foo' }
    fragment = AnnDataFileInfo.new.extract_form_fragment(
      form_segment, :expression,:description, :taxon_id
    )
    assert_equal :expression, fragment[:data_type]
    assert_equal taxon_id, fragment[:taxon_id]
    assert_equal description, fragment[:description]
    assert_nil fragment[:other_data]
  end

  test 'should return obsm_key_names' do
    ann_data_info = AnnDataFileInfo.new(
      data_fragments: [
        { _id: generate_id, data_type: :cluster, name: 'UMAP', obsm_key_name: 'X_umap' },
        { _id: generate_id, data_type: :cluster, name: 'tSNE', obsm_key_name: 'X_tsne' }
      ]
    )
    assert_equal %w[X_umap X_tsne], ann_data_info.obsm_key_names
  end

  test 'should validate data fragments' do
    ann_data_info = AnnDataFileInfo.new(
      data_fragments: [
        { data_type: :cluster, name: 'UMAP', obsm_key_name: 'X_umap' }
      ]
    )
    assert_not ann_data_info.valid?
    error_msg = ann_data_info.errors.messages_for(:data_fragments).first
    assert_equal 'cluster fragment missing one or more required keys: _id', error_msg
    ann_data_info.data_fragments = [
      { _id: generate_id, data_type: :cluster, name: 'UMAP', obsm_key_name: 'X_umap' },
      { _id: generate_id, data_type: :cluster, name: 'UMAP', obsm_key_name: 'X_umap' }
    ]
    assert_not ann_data_info.valid?
    error_messages = ann_data_info.errors.messages_for(:data_fragments)
    assert_equal 2, error_messages.count
    error_messages.each do |message|
      assert message.include?('are not unique')
    end
    ann_data_info.data_fragments = [
      { _id: generate_id, data_type: :cluster, name: 'UMAP', obsm_key_name: 'X_umap' },
      { _id: generate_id, data_type: :cluster, name: 'tSNE', obsm_key_name: 'X_tsne' },
      { _id: generate_id, data_type: :expression, y_axis_title: 'log(TPM) expression' }
    ]
    assert ann_data_info.valid?
  end
end
