class SingleCell
  include Mongoid::Document

  field :name, type: String

  has_many :cluster_points

  belongs_to :study
  belongs_to :study_file
  belongs_to :cluster
  belongs_to :cluster_group

  validates_uniqueness_of :name, scope: [:study_id, :cluster_group_id]

  index({ study_id: 1 }, { unique: false })
  index({ cluster_id: 1 }, { unique: false })
  index({ study_id: 1, cluster_group_id: 1}, {unique: true})

end
