class ClusterGroup
	include Mongoid::Document

	field :name, type: String
	field :cluster_type, type: String
	field :cell_annotations, type: Array

	validates_uniqueness_of :name, scope: :study_id

	belongs_to :study
	belongs_to :study_file
	has_many :data_arrays do
		def by_name_and_type(name, type)
			where(name: name, array_type: type).order_by(&:array_index).to_a
		end
	end
	has_many :cluster_points
	has_many :single_cells

	index({ name: 1, study_id: 1 }, { unique: true })
	index({ study_id: 1 }, { unique: false })

	# maximum number of cells allowed when plotting boxplots
	SUBSAMPLE_THRESHOLD = 1000

	# method to return a single data array of values for a given data array name, annotation name, and annotation value
	# gathers all matching data arrays and orders by index, then concatenates into single array
	def concatenate_data_arrays(array_name, array_type)
		data_arrays = self.data_arrays.by_name_and_type(array_name, array_type)
		all_values = []
		data_arrays.each do |array|
			all_values += array.values
		end
		all_values
	end

	# return number of points in cluster_group, use x axis as all cluster_groups must have either x or y
	def points
		self.concatenate_data_arrays('x', 'coordinates').count
	end

	def is_3d?
		self.cluster_type == '3d'
	end
end