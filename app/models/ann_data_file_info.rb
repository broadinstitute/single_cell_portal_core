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

  # permitted list of data_fragment parameters for sanitizing/validation by data type
  # allows nesting of StudyFile-like objects inside data_fragments
  DATA_FRAGMENT_PARAMS = {
    cluster: %i[
      _id data_type name description obsm_key_name x_axis_label y_axis_label x_axis_min x_axis_max y_axis_min
      y_axis_max z_axis_min z_axis_max external_link_url external_link_title external_link_description
      parse_status spatial_cluster_associations
    ],
    expression: %i[_id data_type taxon_id description expression_file_info y_axis_label raw_location]
  }.freeze

  # required keys for data_fragments, by type
  REQUIRED_FRAGMENT_KEYS = {
    cluster: %i[_id name obsm_key_name], expression: %i[_id taxon_id]
  }.freeze

  field :has_clusters, type: Boolean, default: false
  field :has_metadata, type: Boolean, default: false
  field :has_raw_counts, type: Boolean, default: false
  field :has_expression, type: Boolean, default: false
  # controls whether or not to ingest data (true: should not ingest data, this is like an 'Other' file)
  field :reference_file, type: Boolean, default: true
  # location of raw count data, either .raw attribute or in layers[{name}]
  field :raw_location, type: String, default: ''
  # information from form about data contained inside AnnData file, such as names/descriptions
  # examples:
  # {
  #   _id: '6410b6a9a87b3bbd53fbc351', data_type: :cluster, obsm_key_name: 'X_umap', name: 'UMAP',
  #   description: 'UMAP clustering'
  # }
  # { _id: '6033f531e241391884633748', data_type: :expression, description: 'log(TMP) expression' }
  field :data_fragments, type: Array, default: []
  before_validation :set_default_cluster_fragments!, :set_raw_location!, :sanitize_fragments!
  validate :validate_fragments, :enforce_raw_location
  after_validation :update_expression_file_info

  # collect data frame key_names for clustering data inside AnnData flle
  def obsm_key_names
    data_fragments.map { |f| f.with_indifferent_access[:obsm_key_name] }.compact
  end

  # helper to automatically call :with_indifferent_access on all data_fragments
  def safe_data_fragments
    data_fragments.map(&:with_indifferent_access)
  end

  # handle AnnData upload form data and merge into appropriate fields so that we can make a single update! call
  def merge_form_data(form_data)
    merged_data = form_data.with_indifferent_access
    # merge in existing information about AnnData file, using form data first if present
    anndata_info_attributes = form_data[:ann_data_file_info_attributes] || attributes.with_indifferent_access
    # gotcha to reparse data_fragments from string-encoded JSON form data
    if anndata_info_attributes[:data_fragments].is_a?(String)
      anndata_info_attributes[:data_fragments] = JSON.parse(anndata_info_attributes[:data_fragments]).map(&:with_indifferent_access)
    end
    # merge :reference_anndata_file parameter, if present
    if merged_data[:reference_anndata_file].present? || new_record?
      reference_file = merged_data[:reference_anndata_file].nil? ? true : merged_data[:reference_anndata_file] == 'true'
      anndata_info_attributes[:reference_file] = reference_file
      merged_data.delete(:reference_anndata_file)
    end
    fragments = []
    DATA_TYPE_FORM_KEYS.each do |key, form_segment_name|
      fragment_form = merged_data[form_segment_name]
      next if fragment_form.blank? || fragment_form.empty?

      allowed_params = DATA_FRAGMENT_PARAMS[key]&.reject {|k, _| k == :data_type }
      case key
      when :metadata
        merged_data[:use_metadata_convention] = fragment_form[:use_metadata_convention]
      when :cluster
        fragments << extract_form_fragment(fragment_form, key, *allowed_params)
      when :expression
        merged_data[:taxon_id] = fragment_form[:taxon_id]
        anndata_info_attributes[:raw_location] = merged_data.dig(:expression_file_info_attributes, :raw_location)
        merged_data[:expression_file_info_attributes]&.delete(:raw_location) # prevent UnknownAttribute error
        merged_exp_fragment = fragment_form.merge(expression_file_info: merged_data[:expression_file_info_attributes])
        fragments << extract_form_fragment(merged_exp_fragment, key, *allowed_params)
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
      if existing_frag
        idx = data_fragments.index(existing_frag)
        form_data[:data_fragments][idx] = fragment
      else
        form_data[:data_fragments] << fragment
      end
    end
    form_data
  end

  # find a data_fragment of a given type based on arbitrary key/value pairs
  # any key/value pairs that don't match return false and fail the check for :detect
  # also supports finding values as both strings and symbols (for data_type values)
  def find_fragment(**attrs)
    data_fragments.detect do |fragment|
      !{ **attrs }.map { |k, v| fragment[k] == v || fragment[k] == v.send(transform_for(v)) }.include?(false)
    end
  end

  # get all fragments of a specific data type
  def fragments_by_type(data_type)
    safe_data_fragments.select { |fragment| fragment[:data_type].to_s == data_type.to_s }
  end

  # get the index of a fragment by BSON ObjectId (for making in-place updates)
  def fragment_index_of(fragment)
    id = fragment[:_id] || fragment['_id']
    safe_data_fragments.index { |frag| frag[:_id] == id }
  end

  # mirror of study_file.get_cluster_domain_ranges for data_fragment
  def get_cluster_domain_ranges(name)
    fragment = find_fragment(data_type: :cluster, name:)
    axes = %i[x_axis_min x_axis_max y_axis_min y_axis_max z_axis_min z_axis_max]
    hash_from_keys(fragment, *axes, transform: :to_f)
  end

  # persist information in expression fragment back to expression_file_info object
  def update_expression_file_info
    exp_fragment = find_fragment(data_type: :expression) || fragments_by_type(:expression).first
    exp_info = study_file&.expression_file_info
    return nil if reference_file || exp_fragment.nil? || exp_info.nil?

    info_update = exp_fragment.with_indifferent_access[:expression_file_info]
    info_update.delete(:raw_location) if info_update[:raw_location]
    exp_info.assign_attributes(**info_update) if info_update
  end

  # pull out raw_location from expression fragment and set as top-level attribute for ease of access
  def set_raw_location!
    exp_fragment = find_fragment(data_type: :expression) || fragments_by_type(:expression).first
    return nil if reference_file || exp_fragment.nil?

    self.raw_location = exp_fragment.with_indifferent_access[:raw_location]
  end

  # extract description field from expression fragment to use as axis label
  def expression_axis_label
    exp_fragment = find_fragment(data_type: :expression) || fragments_by_type(:expression).first
    return nil if exp_fragment.nil?

    exp_fragment.with_indifferent_access[:y_axis_label]&.to_s
  end

  private

  # select out keys from source hash and return new one, rejecting blank values
  # will apply transform method if specified, otherwise returns value in place (Object#presence)
  def hash_from_keys(source_hash, *keys, transform: :presence)
    values = keys.map do |key|
      source_hash&.[](key).send(transform) if source_hash&.[](key).present? # skip transform on nil entries
    end
    Hash[keys.zip(values)].reject { |_, v| v.blank? }
  end

  # handle matching values for both strings & symbols when retrieving data_fragments
  def transform_for(value)
    case value.class.name
    when 'String'
      :to_sym
    when 'Symbol'
      :to_s
    else
      :presence
    end
  end

  # reject any extraneous values added from React forms
  def sanitize_fragments!
    sanitized_fragments = []
    safe_data_fragments.each do |fragment|
      sanitized_fragment = {}
      data_type = fragment[:data_type].to_sym
      fragment.each_pair do |key, value|
        sanitized_fragment[key] = value if DATA_FRAGMENT_PARAMS[data_type].include?(key.to_sym)
      end
      sanitized_fragments << sanitized_fragment
    end
    self.data_fragments = sanitized_fragments
  end

  # create the default cluster data_fragment entries
  def set_default_cluster_fragments!
    return false if fragments_by_type(:cluster).any? || reference_file

    default_obsm_keys = AnnDataIngestParameters::PARAM_DEFAULTS[:obsm_keys]
    default_obsm_keys.each do |obsm_key_name|
      name = obsm_key_name.delete_prefix('X_')
      fragment = {
        _id: BSON::ObjectId.new.to_s, data_type: :cluster, name:, obsm_key_name:, spatial_cluster_associations: []
      }
      data_fragments << fragment
    end
  end

  # ensure all fragments have required keys and are unique
  def validate_fragments
    REQUIRED_FRAGMENT_KEYS.each do |data_type, keys|
      fragments = fragments_by_type(data_type)
      fragments.each do |fragment|
        unset_fields_in_exp_fragment(fragment) if data_type == :expression
        missing_keys = keys.map(&:to_s) - fragment.keys.map(&:to_s)
        missing_values = keys.select { |key| fragment[key].blank? }
        next if missing_keys.empty? && missing_values.empty?

        all_missing = (missing_keys + missing_values.map(&:to_s)).uniq
        obsm_key = fragment[:obsm_key_name]
        errors.add(:base,
                   "#{data_type} form #{obsm_key.present? ? "(#{obsm_key}) " : nil}" \
                        "missing one or more required entries: #{all_missing.join(', ')}")
      end
      # check for uniqueness
      keys.each do |key|
        values = fragments.map { |fragment| fragment[key] }
        if values.size > values.uniq.size
          errors.add(:base, "#{key} are not unique in #{data_type} fragments: #{values}")
        end
      end
    end
  end

  def enforce_raw_location
    if study_file.is_raw_counts_file? && !reference_file && raw_location.blank?
      errors.add(:raw_location, 'must have a value for raw count matrices')
    end
  end

  # unset units and raw_location in expression fragment since form data won't have value
  # element must be replaced by index in order to persist
  def unset_fields_in_exp_fragment(fragment)
    exp_info = fragment[:expression_file_info]
    return nil unless exp_info

    unless exp_info[:is_raw_counts]
      exp_info.delete(:units)
      frag_idx = fragment_index_of(fragment)
      data_fragments[frag_idx][:expression_file_info] = exp_info
      data_fragments[frag_idx][:raw_location] = ''
    end
  end
end
