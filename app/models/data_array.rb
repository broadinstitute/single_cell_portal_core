class DataArray
	include Mongoid::Document

	DATA_ARRAY_TYPES = %w(coordinates annotations cells)

	field :name, type: String
	field :cluster_name, type: String
	field :array_type, type: String
	field :array_index, type: Integer
	field :values, type: Array

	belongs_to :study
	belongs_to :study_file
	belongs_to :cluster_group

	index({ name: 1, study_id: 1, cluster_name: 1, array_type: 1, array_index: 1 }, { unique: true })

	# maximum number of entries for values array (to avoid Mongod max document size problems)
	MAX_ENTRIES = 100000

end