class ExpressionScore
  include Mongoid::Document

  belongs_to :study
  belongs_to :study_file

  field :gene, type: String
  field :searchable_gene, type: String
  field :scores, type: Hash

  index({searchable_gene: 1}, {unique: false})
  index({ gene: 1, study_id: 1 }, { unique: true })

  def mean(cells)
    sum = 0.0
    cells.each do |cell|
      sum += self.scores[cell].to_f
    end
    sum / cells.size
  end

end
