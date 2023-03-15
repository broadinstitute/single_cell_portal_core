class AnnDataFileInfo
  include Mongoid::Document

  embedded_in :study_file

  field :has_clusters, type: Boolean, default: false
  field :has_metadata, type: Boolean, default: false
  field :has_raw_counts, type: Boolean, default: false
  field :has_expression, type: Boolean, default: false
  field :obsm_key_names, type: Array, default: []
  field :other_form_fields_info, type: Hash, default: {}
end