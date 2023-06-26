# top-level info about DE results contained in a user-uploaded file
class DifferentialExpressionFileInfo
  include Mongoid::Document
  include Annotatable # handles getting/setting annotation objects

  embedded_in :study_file
  belongs_to :cluster_group

  field :annotation_name, type: String
  field :annotation_scope, type: String
  field :computational_method, type: String, default: DifferentialExpressionResult::DEFAULT_COMP_METHOD
  field :clustering_association, type: String # associated clustering StudyFile, for upload UI

  validates :annotation_name, presence: true, uniqueness: { scope: %i[annotation_scope cluster_group] }
  validates :annotation_scope, presence: true
  validate :annotation_exists?

  before_validation :set_cluster_from_association

  delegate :study, to: :study_file

  private

  def set_cluster_from_association
    self.cluster_group_id = instance_from_study_file_id(clustering_association, ClusterGroup)
  end
end
