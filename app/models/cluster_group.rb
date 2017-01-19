class ClusterGroup
	include Mongoid::Document

	field :name, type: String
	field :cluster_type, type: String
	field :cell_annotations, type: Array

	validates_uniqueness_of :name, scope: :study_id

	belongs_to :study
	belongs_to :study_file
	has_many :cluster_points
	has_many :single_cells

	index({ name: 1, study_id: 1 }, { unique: true })
	index({ study_id: 1 }, { unique: false })

	# maximum number of cells allowed when plotting boxplots
	SUBSAMPLE_THRESHOLD = 1000
end