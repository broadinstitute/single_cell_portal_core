# top-level info about DE results contained in a user-uploaded file
class DifferentialExpressionFileInfo
  include Mongoid::Document
  include Annotatable # handles getting/setting annotation objects

  embedded_in :study_file
  belongs_to :cluster_group

  field :annotation_name, type: String
  field :annotation_scope, type: String
  field :computational_method, type: String, default: DifferentialExpressionResult::DEFAULT_COMP_METHOD
  field :significance_metric, type: String
  field :size_metric, type: String
  field :clustering_association, type: String # associated clustering StudyFile, for upload UI

  validates :annotation_name, presence: true, uniqueness: { scope: %i[annotation_scope cluster_group] }
  validates :annotation_scope, presence: true
  validates :significance_metric, presence: true
  validates :size_metric, presence: true
  validate :annotation_exists?

  before_validation :set_cluster_from_association, on: :create

  delegate :study, to: :study_file

  private

  # handle setting association to ClusterGroup from form file ID
  def set_cluster_from_association
    self.cluster_group = instance_from_study_file_id(clustering_association, ClusterGroup) unless cluster_group
  end
end
