class Gene
  include Mongoid::Document

  belongs_to :study
  belongs_to :study_file
  has_many :data_arrays, as: :linear_data

  field :name, type: String
  field :searchable_name, type: String
  field :gene_id, type: String

  index({ name: 1, study_id: 1, study_file_id: 1 }, { unique: false, background: true})
  index({ gene_id: 1, study_id: 1, study_file_id: 1 }, { unique: false, background: true})
  index({ searchable_name: 1, study_id: 1, study_file_id: 1 }, { unique: false, background: true })
  index({ study_id: 1, study_file_id: 1} , { unique: false, background: true })

  validates_uniqueness_of :name, scope: [:study_id, :study_file_id, :gene_id]
  validates_presence_of :name

  ##
  # INSTANCE METHODS
  ##

  # concatenate all the necessary data_array objects and construct a hash of cell names => expression values
  def scores
    cells = self.concatenate_data_arrays(self.cell_key, 'cells')
    exp_values = self.concatenate_data_arrays(self.score_key, 'expression')
    Hash[cells.zip(exp_values)]
  end

  # key to retrieve data arrays of cell names for this gene
  def cell_key
    "#{self.name} Cells"
  end

  # key to retrieve data arrays of expression values for this gene
  def score_key
    "#{self.name} Expression"
  end

  # concatenate data arrays of a given name/type in order
  def concatenate_data_arrays(array_name, array_type)
    data_arrays = DataArray.where(name: array_name, array_type: array_type, linear_data_type: 'Gene',
                                  linear_data_id: self.id).order(:array_index => 'asc')
    all_values = []
    data_arrays.each do |array|
      all_values += array.values
    end
    all_values
  end

  def autocomplete_label
    self.gene_id.blank? ? self.name : "#{self.name} (#{self.gene_id})"
  end

  def taxon
    self.study_file.taxon
  end

  def species
    self.study_file.taxon
  end

  ##
  # CLASS INSTANCE METHODS
  ##

  # find if a study has a given gene quickly for search gating
  def self.study_has_gene?(study_id:, expr_matrix_ids:, gene_name:)
    Gene.where(study_id: study_id, :study_file_id.in => expr_matrix_ids).any_of({name: gene_name},{searchable_name: gene_name.downcase}).exists?
  end

  # calculate a mean value for a given gene based on merged expression scores hash
  def self.mean(scores, cells)
    values = cells.map {|c| scores[c].to_f}
    values.mean
  end

  # calculate a median value for a given gene based on merged expression scores hash
  def self.median(scores, cells)
    values = cells.map {|c| scores[c].to_f}
    self.array_median(values)
  end

  # calculate median of an array
  def self.array_median(values)
    sorted_values = values.sort
    len = sorted_values.length
    (sorted_values[(len - 1) / 2] + sorted_values[len / 2]) / 2.0
  end

  # calculate the z-score of an array
  def self.array_z_score(values)
    mean = values.mean
    stddev = values.stdev
    if stddev === 0.0
      # if the standard deviation is zero, return NaN for all values (to avoid getting Infinity)
      values.map {Float::NAN}
    else
      values.map {|v| (v - mean) / stddev}
    end
  end

  # calculate a z-score for every entry (subtract the mean, divide by the standard deviation)
  # for a given gene based on merged expression scores hash
  def self.z_score(scores, cells)
    values = cells.map {|c| scores[c].to_f}
    self.array_z_score(values)
  end

  # calculate the robust z-score of an array of values
  def self.array_robust_z_score(values)
    median = self.array_median(values)
    deviations = values.map {|v| (v - median).abs}
    # compute median absolute deviation
    mad = self.array_median(deviations)
    if mad === 0.0
      # if the median absolute deviation is zero, return NaN for all values (to avoid getting Infinity)
      values.map {Float::NAN}
    else
      values.map {|v| (v - median) / mad}
    end
  end

  # calculate a robust z-score for every entry (subtract the median, divide by the median absolute deviation)
  # for a given gene based on merged expression scores hash
  def self.robust_z_score(scores, cells)
    values = cells.map {|c| scores[c].to_f}
    self.array_robust_z_score(values)
  end

  ##
  # Migration Methods
  ##

  # tease out gene IDs from names, where present
  def self.add_gene_ids_to_genes
    Rails.logger.info "Migrating genes - adding gene_id"
    study_files = StudyFile.where(file_type: 'MM Coordinate Matrix')
    study_file_count = study_files.count
    study_files.each_with_index do |study_file, study_file_index|
      genes = Gene.where(study_id: study_file.study.id, study_file_id: study_file.id, gene_id: nil) # only process genes without a gene_id
      gene_count = genes.count
      genes.each_with_index do |gene, gene_index|
        current_name = gene.name
        new_name, gene_id = current_name.split('(').map {|entry| entry.strip.chomp(')')}
        gene.update(name: new_name, searchable_name: new_name.downcase, gene_id: gene_id)
        if (gene_index + 1) % 1000 == 0
          Rails.logger.info "Processed #{gene_index + 1}/#{gene_count} records from file #{study_file_index + 1} of #{study_file_count}"
        end
      end
    end
    Rails.logger.info "Data reformatting complete, reindexing Gene collection"
    Gene.remove_indexes
    Gene.create_indexes
    Rails.logger.info "Migration complete"
  end

  # revert back to combined gene names/ids
  def self.remove_gene_ids_from_genes
    Rails.logger.info "Rolling back migration - removing gene_id"
    genes = Gene.where(:gene_id.nin => [nil])
    gene_count = genes.count
    genes.each_with_index do |gene, gene_index|
      old_name = "#{gene.name} (#{gene.gene_id})"
      gene.update(name: old_name, searchable_name: old_name.downcase, gene_id: nil)
      if (gene_index + 1) % 1000 == 0
        Rails.logger.info "Processed #{gene_index + 1}/#{gene_count} records"
      end
    end
    Rails.logger.info "Data reformatting complete, reindexing Gene collection"
    Gene.remove_indexes
    Gene.create_indexes
    Rails.logger.info "Rollback complete"
  end
end
