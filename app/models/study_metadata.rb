class StudyMetadata
  include Mongoid::Document

  belongs_to :study
  belongs_to :study_file

  field :name, type: String
  field :annotation_type, type: String
  field :cell_annotations, type: Hash
  field :values, type: Array

  index({ name: 1, annotation_type: 1, study_id: 1 }, { unique: false })

  MAX_ENTRIES = 100000
end
