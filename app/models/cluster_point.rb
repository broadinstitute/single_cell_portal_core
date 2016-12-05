class ClusterPoint
  include Mongoid::Document

  belongs_to :single_cell
  belongs_to :cluster
  belongs_to :study_file
  belongs_to :study

  field :x, type: Float
  field :y, type: Float
  field :cell_name, type: String

  index({ single_cell_id: 1 }, { unique: false })
  index({ cluster_id: 1 }, { unique: false })
  index({ study_id: 1 }, { unique: false })

end
