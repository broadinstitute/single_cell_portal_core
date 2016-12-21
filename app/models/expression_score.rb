class ExpressionScore
  include Mongoid::Document

  belongs_to :study
  belongs_to :study_file

  field :gene, type: String
  field :scores, type: Hash

  index({ gene: 1, study_id: 1 }, { unique: true })

  validates_uniqueness_of :gene, scope: :study_id

  def mean(cells)
    sum = 0.0
    cells.each do |cell|
      sum += self.scores[cell].to_f
    end
    sum / cells.size
  end

end
