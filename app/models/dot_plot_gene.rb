class DotPlotGene
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :study
  belongs_to :study_file # expression matrix, not clustering file
  belongs_to :cluster_group

  field :gene_symbol, type: String
  field :searchable_gene, type: String
  field :exp_scores, type: Hash, default: {}

  validates :study, :study_file, :cluster_group, presence: true
  validates :gene_symbol, uniqueness: { scope: %i[study study_file cluster_group] }, presence: true

  before_validation :set_searchable_gene, on: :create

  def scores_by_annotation(annotation_name, annotation_scope, values)
    identifier = "#{annotation_name}--group--#{annotation_scope}"
    scores = exp_scores[identifier] || {}
    values.map { |val| scores[val] || [0.0, 0.0] }
  end

  private

  def set_searchable_gene
    self.searchable_gene = gene_symbol.downcase
  end
end
