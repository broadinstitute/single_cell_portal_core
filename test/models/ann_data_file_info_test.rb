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
          y_axis_max: '10',
          external_link_url: 'https://example.com',
          external_link_title: 'Example Link',
          external_link_description: 'This is an external link'
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
    assert_equal 'https://example.com', cluster_fragment[:external_link_url]
    assert_equal 'Example Link', cluster_fragment[:external_link_title]
    assert_equal 'This is an external link', cluster_fragment[:external_link_description]
    expr_fragment = merged_data.dig(root_form_key, :data_fragments).detect { |f| f[:data_type] == :expression }
    assert_equal 'expression description', expr_fragment[:description]
    assert_equal 'log(TPM) expression', expr_fragment[:y_axis_label]
  end

  test 'should decode serialized JSON form data' do
    data_fragments = [
      {
        _id: generate_id, data_type: 'expression', taxon_id: generate_id
      }.with_indifferent_access,
      {
        _id: generate_id, data_type: 'cluster', name: 'UMAP', description: 'UMAP description', obsm_key_name: 'X_umap'
      }.with_indifferent_access
    ]
    form_params = {
      ann_data_file_info_attributes: {
        _id: generate_id,
        reference_file: false,
        data_fragments: data_fragments.to_json
      }
    }
    merged_data = AnnDataFileInfo.new.merge_form_data(form_params)
    safe_fragments = merged_data.dig(:ann_data_file_info_attributes, :data_fragments).map(&:with_indifferent_access)
    assert_equal data_fragments, safe_fragments
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

  test 'should set default cluster fragments' do
    ann_data_info = AnnDataFileInfo.new(reference_file: false)
    assert ann_data_info.valid?
    default_keys = AnnDataIngestParameters::PARAM_DEFAULTS[:obsm_keys]
    default_keys.each do |obsm_key_name|
      name = obsm_key_name.delete_prefix('X_')
      matcher = { data_type: :cluster, name:, obsm_key_name: }.with_indifferent_access
      assert ann_data_info.find_fragment(**matcher).present?
    end
    # ensure non-parseable AnnData files don't create fragment
    reference_anndata = AnnDataFileInfo.new
    assert reference_anndata.valid?
    assert_empty reference_anndata.data_fragments
    assert_empty reference_anndata.obsm_key_names
  end

  test 'should validate data fragments' do
    ann_data_info = AnnDataFileInfo.new(
      data_fragments: [
        { data_type: :cluster, name: 'UMAP', obsm_key_name: 'X_umap' },
        { data_type: :expression }
      ]
    )
    assert_not ann_data_info.valid?
    cluster_error_msg = ann_data_info.errors.messages_for(:base).first
    assert_equal 'cluster form (X_umap) missing one or more required entries: _id', cluster_error_msg
    exp_error_msg = ann_data_info.errors.messages_for(:base).last
    assert_equal 'expression form missing one or more required entries: _id, taxon_id', exp_error_msg
    ann_data_info.data_fragments = [
      { _id: generate_id, data_type: :cluster, name: 'UMAP', obsm_key_name: 'X_umap' },
      { _id: generate_id, data_type: :cluster, name: 'UMAP', obsm_key_name: 'X_umap' }
    ]
    assert_not ann_data_info.valid?
    error_messages = ann_data_info.errors.messages_for(:base)
    assert_equal 2, error_messages.count
    error_messages.each do |message|
      assert message.include?('are not unique')
    end
    ann_data_info.data_fragments = [
      { _id: generate_id, data_type: :cluster, name: '', obsm_key_name: 'X_umap' },
      { _id: generate_id, data_type: :cluster, name: nil, obsm_key_name: 'X_tsne' }
    ]
    assert_not ann_data_info.valid?
    error_messages = ann_data_info.errors.messages_for(:base)
    assert_equal 2, error_messages.count
    error_messages.each do |message|
      assert message.match(/cluster form \((X_umap|X_tsne)\) missing one or more required entries/)
    end
    ann_data_info.data_fragments = [
      { _id: generate_id, data_type: :cluster, name: 'UMAP', obsm_key_name: 'X_umap' },
      { _id: generate_id, data_type: :cluster, name: 'tSNE', obsm_key_name: 'X_tsne' },
      {
        _id: generate_id, data_type: :expression, y_axis_title: 'log(TPM) expression',
        taxon_id: BSON::ObjectId.new.to_s
      }
    ]
    assert ann_data_info.valid?
  end

  test 'should propagate expression_file_info when saving' do
    user = FactoryBot.create(:user, registered_for_firecloud: true, test_array: @@users_to_clean)
    study = FactoryBot.create(:detached_study, user:, name_prefix: 'AnnData Save Test', test_array: @@studies_to_clean)
    ann_data_file = FactoryBot.create(:ann_data_file,
                                      name: 'test.h5ad',
                                      study:,
                                      cell_input: %w[bar bing],
                                      expression_input: {
                                        'foo' => [['bar', 0.3], ['bing', 1.0]]
                                      })
    assert_not ann_data_file.expression_file_info.is_raw_counts?
    assert_equal 'Whole cell', ann_data_file.expression_file_info.biosample_input_type
    ann_data_file.ann_data_file_info.reference_file = false
    expression_file_info = {
      library_preparation_protocol: "10x 5' v3",
      biosample_input_type: 'Single nuclei',
      modality: 'Transcriptomic: targeted',
      is_raw_counts: true,
      units: 'raw counts'
    }
    ann_data_file.ann_data_file_info.data_fragments = [
      { _id: generate_id, data_type: :cluster, obsm_key_name: 'X_umap', name: 'UMAP' },
      { _id: generate_id, data_type: :expression, taxon_id: generate_id, expression_file_info: }
    ]
    ann_data_file.save!
    ann_data_file.reload
    expression_file_info.each do |attr, val|
      assert_equal val, ann_data_file.expression_file_info.send(attr)
    end
  end

  test 'should find index of fragment' do
    anndata_info = AnnDataFileInfo.new(
      data_fragments: [
        { _id: generate_id, data_type: :cluster, name: 'UMAP', obsm_key_name: 'X_umap' },
        { _id: generate_id, data_type: :cluster, name: 'tSNE', obsm_key_name: 'X_tsne' },
        { _id: generate_id, data_type: :expression, y_axis_title: 'log(TPM) expression' }
      ]
    )
    0.upto(anndata_info.data_fragments.size - 1).each_with_index do |idx|
      fragment = anndata_info.data_fragments[idx]
      assert_equal idx, anndata_info.fragment_index_of(fragment)
    end
  end

  test 'should unset units in expression fragment if not raw counts' do
    anndata_info = AnnDataFileInfo.new(
      data_fragments: [
        {
          _id: generate_id, data_type: :expression, taxon_id: generate_id,
          expression_file_info: {
            library_preparation_protocol: "10x 5' v3",
            biosample_input_type: 'Single nuclei',
            modality: 'Transcriptomic: targeted',
            is_raw_counts: false,
            units: 'raw counts'
          }
        }.with_indifferent_access
      ]
    )
    assert anndata_info.valid? # invokes validations
    exp_frag = anndata_info.fragments_by_type(:expression).first
    assert_nil exp_frag.with_indifferent_access.dig(:expression_file_info, :units)
  end
end
