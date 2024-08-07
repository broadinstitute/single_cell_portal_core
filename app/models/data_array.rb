class DataArray

  ###
  #
  # DataArray: child class of ClusterGroup & StudyFile, stores linear arrays of data (x/y/z coordinates, or annotation values)
  #
  ###

  include Mongoid::Document
  extend Concatenatable

  DATA_ARRAY_TYPES = %w(coordinates annotations cells expression)

  field :name, type: String
  field :cluster_name, type: String # this is actually the entity name from which it was derived (i.e. name of study_file)
  field :array_type, type: String
  field :array_index, type: Integer
  field :values, type: Array
  field :subsample_threshold, type: Integer
  field :subsample_annotation, type: String
  field :cluster_group_id, type: BSON::ObjectId
  belongs_to :study
  belongs_to :study_file
  belongs_to :linear_data, polymorphic: true

  index({ name: 1, study_id: 1, cluster_group_id: 1, linear_data_type: 1, linear_data_id: 1, cluster_name: 1,
                array_type: 1, array_index: 1, subsample_threshold: 1, subsample_annotation: 1 },
        { unique: true, name: 'linear_data_arrays_index', background: true })
  index({ study_id: 1, study_file_id: 1}, { unique: false, background: true })
  index({ study_id: 1, linear_data_id: 1}, { unique: false, background: true })

  validates_presence_of :name, :cluster_name, :array_type, :array_index, :values
  validates_uniqueness_of :name, scope: [:study_id, :cluster_name, :linear_data_type, :linear_data_id, :array_type,
                                         :array_index, :subsample_threshold, :subsample_annotation]

  # maximum number of entries for values array (to avoid MongoDB max document size problems)
  MAX_ENTRIES = 100000
end
