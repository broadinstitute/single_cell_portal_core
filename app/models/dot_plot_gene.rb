class DotPlotGene
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :study
  belongs_to :study_file # expression matrix, not clustering file - needed for data cleanup
  belongs_to :cluster_group

  field :gene_symbol, type: String
  field :searchable_gene, type: String
  field :exp_scores, type: Hash, default: {}

  validates :study, :study_file, :cluster_group, presence: true
  validates :gene_symbol, uniqueness: { scope: %i[study study_file cluster_group] }, presence: true

  before_validation :set_searchable_gene, on: :create
  index({ study_id: 1, study_file_id: 1, cluster_group_id: 1 }, { unique: false, background: true })
  index({ study_id: 1, cluster_group_id: 1, searchable_gene: 1 },
        { unique: true, background: true })

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
