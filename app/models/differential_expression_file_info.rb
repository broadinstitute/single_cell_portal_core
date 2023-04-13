# top-level info about DE results contained in a user-uploaded file
class DifferentialExpressionFileInfo
  include Mongoid::Document
  include Annotatable # handles getting/setting annotation objects

  embedded_in :study_file
  belongs_to :cluster_group

  field :annotation_name, type: String
  field :annotation_scope, type: String
  field :computational_method, type: String, default: DifferentialExpressionResult::DEFAULT_COMP_METHOD

  validates :computational_method, inclusion: { in: DifferentialExpressionResult::SUPPORTED_COMP_METHODS }
  validates :annotation_name, presence: true, uniqueness: { scope: %i[annotation_scope cluster_group] }
  validates :annotation_scope, presence: true
  validate :annotation_exists?

  delegate :study, to: :study_file
end
