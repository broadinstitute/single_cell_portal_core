class ExpressionFileInfo
  include Mongoid::Document

  embedded_in :study_file

  field :library_preparation_protocol, type: String
  field :units, type: String
  field :biosample_input_type, type: String, default: 'Whole cell'
  field :modality, type: String, default: 'Transcriptomic: unbiased'
  field :is_raw_counts, type: Boolean, default: false
  field :raw_counts_associations, type: Array, default: []

  before_validation :sanitize_raw_counts_associations

  # note that species and reference genome/annotation live at the study_file level, not here

  UNITS_VALUES = ['UMI-corrected raw counts', 'raw counts'].freeze
  validates :units, inclusion: { in: UNITS_VALUES }, allow_blank: true

  BIOSAMPLE_INPUT_TYPE_VALUES = ['Whole cell', 'Single nuclei', 'Bulk'].freeze
  validates :biosample_input_type, inclusion: { in: BIOSAMPLE_INPUT_TYPE_VALUES }

  MODALITY_VALUES = [
    'Transcriptomic: unbiased',
    'Transcriptomic: targeted',
    'Spatial transcriptomics',
    'Epigenomic: DNA-binding: histone modification',
    'Epigenomic: DNA-binding: transcriptome factor location',
    'Epigenomic: DNA chromatin accessibility',
    'Epigenomic: DNA methylation',
    'Proteomic'
  ].freeze
  validates :modality, inclusion: { in: MODALITY_VALUES }

  LIBRARY_PREPARATION_VALUES = [
                                "10x 3' v1", # scRNAseq
                                "10x 3' v2", # scRNAseq
                                "10x 3' v3", # scRNAseq
                                "10x 5' v1", # scRNAseq
                                "10x 5' v2", # scRNAseq
                                "10x 5' v3", # scRNAseq
                                '10x feature barcode/cell surface protein', # targeted proteomic
                                '10x feature barcode/CRISPR', # expression perturbation
                                '10x feature barcode/multiplexing', # scRNAseq
                                '10x Ig enrichment', # targeted transcriptomic
                                '10x multiome', # multiomic ATAC-seq
                                '10x scATAC-seq', # scATAC-seq
                                '10x TCR enrichment', # targeted transcriptomic
                                '10x Visium', # spatial transcriptomic
                                'CEL-seq2', # scRNAseq
                                'Drop-ChIP', # scChIP-seq
                                'Drop-seq', # scRNAseq
                                'dsc-ATAC-seq', # scATAC-seq
                                'dsci-ATAC-seq', # scATAC-seq
                                'inDrop', # scRNAseq
                                'MARS-seq', # scRNAseq
                                'MERFISH', # spatial transcriptomic
                                'osmFISH', # spatial transcriptomic
                                'scATAC-seq/Fluidigm', # scATAC-seq
                                'sci-ATAC-seq', # scATAC-seq
                                'sci-RNA-seq', # scRNAseq
                                'scTHS-seq', # scATAC-seq
                                'Seq-Well S^3', # scRNAseq
                                'Seq-Well v1', # scRNAseq
                                'SeqFISH+', # spatial transcriptomic
                                'SHARE-seq', # multiomic ATAC-seq
                                'Slide-seq', # spatial transcriptomic
                                'Slide-seqV2', # spatial transcriptomic
                                'Slide-tags',
                                'Smart-like', # scRNAseq
                                'Smart-seq2/Fluidigm C1', # scRNAseq
                                'Smart-seq2/plate-based', # scRNAseq
                                'smFISH', # spatial transcriptomic
                                'snATAC-seq', # scATAC-seq
                                'STARmap',  # spatial transcriptomic
                              ].freeze
  validates :library_preparation_protocol, inclusion: { in: LIBRARY_PREPARATION_VALUES }

  validate :unset_units_unless_raw_counts
  validate :enforce_units_on_raw_counts
  validate :enforce_raw_counts_associations, unless: proc { |attributes| attributes[:is_raw_counts] }
  private

  # remove invalid StudyFile ids, as well as nil/empty string values
  def sanitize_raw_counts_associations
    invalid_ids = raw_counts_associations.select { |study_file_id| StudyFile.find(study_file_id).nil? }
    raw_counts_associations.reject! { |study_file_id| study_file_id.blank? || invalid_ids.include?(study_file_id) }
  end

  # unset the value for :units unless :is_raw_counts is true
  # this has to be invoked as a validation as callbacks only fire on parent document (StudyFile)
  def unset_units_unless_raw_counts
    unless self.is_raw_counts
      self.units = nil unless self.frozen? # document will be frozen if it is being unset, so don't attempt update
    end
  end

  # enforce selecting units on raw count matrices
  def enforce_units_on_raw_counts
    if self.is_raw_counts && self.units.blank?
      errors.add(:units, ' must have a value for raw count matrices')
    end
  end

  # enforce assigning associations on "processed" expression matrix files
  # will check for exemption from any users associated with given study
  def enforce_raw_counts_associations
    raw_counts_required = FeatureFlag.find_by(name: 'raw_counts_required_backend')
    return true if raw_counts_required.nil? || raw_counts_required.default_value == false || study_file.is_anndata?

    # first ensure raw matrix is present
    if raw_counts_associations.any?
      raw_counts_associations.each do |study_file_id|
        raw_matrix = StudyFile.find(study_file_id)
        # enforce bundle completion on matrix, if needed
        # if matrix does not need to be bundled (e.g. is dense), then return true for is_completed
        is_completed = raw_matrix&.should_bundle? ? raw_matrix.has_completed_bundle? : true
        return true if raw_matrix&.is_raw_counts_file? && is_completed
      end
    end

    # next check for exemption across all associated users & study object
    user_accounts = study_file.study.associated_users(permission: 'Edit')
    unless FeatureFlaggable.flag_override_for_instances(
      'raw_counts_required_backend', false, *user_accounts, study_file.study
    )
      errors.add(
        :base, 'You must specify at least one associated raw count file before saving.  Raw count files in sparse ' \
               '(MTX) format must also include associated features/barcodes files.'
      )
    end
  end
end
