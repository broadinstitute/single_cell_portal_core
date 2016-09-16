class PrecomputedScore
	include Mongoid::Document

	belongs_to :study
	belongs_to :study_file

	field :name, type: String
	field :clusters, type: Array
	field :gene_scores, type: Array

	index({ study_id: 1 }, { unique: false })

	def gene_list
		self.gene_scores.map(&:keys).flatten
	end
end