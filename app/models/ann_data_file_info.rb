# stores info about data that has been extracted from AnnData (.h5ad) files
class AnnDataFileInfo
  include Mongoid::Document
  embedded_in :study_file

  # key of fragment data_type to form key name
  DATA_TYPE_FORM_KEYS = {
    expression: 'extra_expression_form_info_attributes',
    metadata: 'metadata_form_info_attributes',
    cluster: 'cluster_form_info_attributes'
  }.freeze

  # permitted list of data_fragment strong parameters
  # allows nesting of StudyFile-like objects inside data_fragments
  DATA_FRAGMENT_PARAMS = [
    :_id, :data_type, :name, :description, :obsm_key_name, :x_axis_label, :y_axis_label, :x_axis_min, :x_axis_max,
    :y_axis_min, :y_axis_max, :z_axis_min, :z_axis_max, :taxon_id,
    { spatial_cluster_associations: [] },
    { expression_file_info: ExpressionFileInfo.attribute_names }
  ].freeze

  # required keys for data_fragments, by type
  REQUIRED_FRAGMENT_KEYS = {
    cluster: %i[_id name obsm_key_name], expression: %i[_id]
  }.freeze

  field :has_clusters, type: Boolean, default: false
  field :has_metadata, type: Boolean, default: false
  field :has_raw_counts, type: Boolean, default: false
  field :has_expression, type: Boolean, default: false
  # controls whether or not to ingest data (true: should not ingest data, this is like an 'Other' file)
  field :reference_file, type: Boolean, default: true
  # information from form about data contained inside AnnData file, such as names/descriptions
  # examples:
  # {
  #   _id: '6410b6a9a87b3bbd53fbc351', data_type: :cluster, obsm_key_name: 'X_umap', name: 'UMAP',
  #   description: 'UMAP clustering'
  # }
  # { _id: '6033f531e241391884633748', data_type: :expression, description: 'log(TMP) expression' }
  field :data_fragments, type: Array, default: []
  validate :validate_fragments

  # collect data frame key_names for clustering data inside AnnData flle
  def obsm_key_names
    data_fragments.map { |f| f[:obsm_key_name] }.compact
  end

  # handle AnnData upload form data and merge into appropriate fields so that we can make a single update! call
  def merge_form_data(form_data)
    merged_data = form_data.with_indifferent_access
    # merge in existing information about AnnData file, using form data first if present
    anndata_info_attributes = form_data[:ann_data_file_info_attributes] || attributes.with_indifferent_access
    # check value of :reference_anndata_file which is passed as a string
    # it is not present in 'classic mode' so the absence of it means this is a reference upload
    reference_file = merged_data[:reference_anndata_file].nil? ? true : merged_data[:reference_anndata_file] == 'true'
    anndata_info_attributes[:reference_file] = reference_file
    merged_data.delete(:reference_anndata_file)
    fragments = []
    DATA_TYPE_FORM_KEYS.each do |key, form_segment_name|
      fragment_form = merged_data[form_segment_name]
      next if fragment_form.blank? || fragment_form.empty?

      case key
      when :metadata
        merged_data[:use_metadata_convention] = fragment_form[:use_metadata_convention]
      when :cluster
        fragments << extract_form_fragment(
          fragment_form, key,
          :_id, :name, :description, :obsm_key_name, :x_axis_label, :y_axis_label, :x_axis_min, :x_axis_max,
          :y_axis_min, :y_axis_max, :z_axis_min, :z_axis_max, :spatial_cluster_associations
        )
      when :expression
        merged_data[:taxon_id] = fragment_form[:taxon_id]
        merged_exp_fragment = fragment_form.merge(expression_file_info: merged_data[:expression_file_info_attributes])
        fragments << extract_form_fragment(
          merged_exp_fragment, key, :_id, :description, :y_axis_label, :taxon_id, :expression_file_info
        )
      end
      # remove from form data once processed to allow normal save of nested form data
      merged_data.delete(form_segment_name)
    end
    merged_data[:ann_data_file_info_attributes] = merge_form_fragments(anndata_info_attributes, fragments)
    merged_data
  end

  # extract out a single fragment to append to the entire form later under :data_fragments
  # stores information about individual data types, such as names/descriptions or axis info
  def extract_form_fragment(form_segment, fragment_type, *keys)
    safe_segment = form_segment.with_indifferent_access
    fragment = hash_from_keys(safe_segment, *keys)
    fragment[:data_type] = fragment_type
    fragment
  end

  # merge in form fragments and finalize data for saving
  def merge_form_fragments(form_data, fragments)
    fragments.each do |fragment|
      keys = %i[_id data_type]
      matcher = hash_from_keys(fragment, *keys)
      existing_frag = find_fragment(**matcher)
      idx = existing_frag ? data_fragments.index(existing_frag) : data_fragments.size
      form_data[:data_fragments].insert(idx, fragment)
    end
    form_data
  end

  # find a data_fragment of a given type based on arbitrary key/value pairs
  # any key/value pairs that don't match return false and fail the check for :detect
  def find_fragment(**attrs)
    data_fragments.detect do |fragment|
      !{ **attrs }.map { |k, v| fragment[k] == v }.include?(false)
    end
  end

  # get all fragments of a specific data type
  def fragments_by_type(data_type)
    data_fragments.select { |fragment| fragment[:data_type].to_s == data_type.to_s }
  end

  # mirror of study_file.get_cluster_domain_ranges for data_fragment
  def get_cluster_domain_ranges(name)
    fragment = find_fragment(data_type: :cluster, name:)
    axes = %i[x_axis_min x_axis_max y_axis_min y_axis_max z_axis_min z_axis_max]
    hash_from_keys(fragment, *axes, transform: :to_f)
  end

  private

  # select out keys from source hash and return new one, rejecting blank values
  # will apply transform method if specified, otherwise returns value in place (Object#presence)
  def hash_from_keys(source_hash, *keys, transform: :presence)
    values = keys.map do |key|
      source_hash[key].send(transform) if source_hash[key].present? # skip transform on nil entries
    end
    Hash[keys.zip(values)].reject { |_, v| v.blank? }
  end

  # ensure all fragments have required keys and are unique
  def validate_fragments
    REQUIRED_FRAGMENT_KEYS.each do |data_type, keys|
      fragments = fragments_by_type(data_type)
      fragments.each do |fragment|
        missing_keys = keys.map(&:to_s) - fragment.keys.map(&:to_s)
        if missing_keys.any?
          errors.add(:data_fragments,
                     "#{data_type} fragment missing one or more required keys: #{missing_keys.join(',')}")
        end
      end
      # check for uniqueness
      keys.each do |key|
        values = fragments.map { |fragment| fragment[key] }
        if values.size > values.uniq.size
          errors.add(:data_fragments, "#{key} are not unique in #{data_type} fragments: #{values}")
        end
      end
    end
  end
end
