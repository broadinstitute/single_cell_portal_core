class ExpressionFileInfo
  include Mongoid::Document

  embedded_in :study_file

  field :library_preparation_protocol, type: String
  field :units, type: String
  field :biosample_input_type, type: String
  field :modality, type: String
  field :is_raw_counts, type: Boolean, default: false

  # note that species and reference genome/annotation live at the study_file level, not here

  UNITS_VALUES = ['UMI-corrected raw counts', 'raw counts']
  validates :units, inclusion: {in: UNITS_VALUES}, allow_blank: true

  BIOSAMPLE_INPUT_TYPE_VALUES = ['Whole cell', 'Single nuclei', 'Bulk']
  validates :biosample_input_type, inclusion: {in: BIOSAMPLE_INPUT_TYPE_VALUES}, allow_blank: true

  MODALITY_VALUES = [
    'Transcriptomic: unbiased',
    'Transcriptomic: targeted',
    'Spatial transcriptomics',
    'Epigenomic: DNA-binding: histone modification',
    'Epigenomic: DNA-binding: transcriptome factor location',
    'Epigenomic: DNA chromatin accessibility',
    'Epigenomic: DNA methylation',
    'Proteomic'
  ]
  validates :modality, inclusion: {in: MODALITY_VALUES}, allow_blank: true

  LIBRARY_PREPARATION_VALUES = ['10x 3\' v1',
                                '10x 3\' v2',
                                '10x 3\' v3',
                                '10x 5\' v2',
                                '10x 5\' v3',
                                'CEL-seq2',
                                'Drop-seq',
                                'inDrop',
                                'MARS-seq',
                                'sci-RNA-seq',
                                'Seq-Well S^3',
                                'Seq-Well v1',
                                'Smart-like',
                                'Smart-seq2/Fluidigm C1',
                                'Smart-seq2/plate-based',
                                # non-scRNAseq Assays
                                # single cell ATAC-seq assays
                                'dsc-ATAC-seq',
                                'dsci-ATAC-seq',
                                'scATAC-seq/10x',
                                'scATAC-seq/Fluidigm',
                                'sci-ATAC-seq',
                                'scTHS-seq',
                                'snATAC-seq',
                                # spatial transcriptomics assays
                                '10x Visium',
                                'MERFISH',
                                'osmFISH',
                                'SeqFISH+',
                                'Slide-seq',
                                'smFISH',
                                # single cell ChIP-seq assays
                                'Drop-ChIP']
  validates :library_preparation_protocol, inclusion: {in: LIBRARY_PREPARATION_VALUES}, allow_blank: true

  validate :unset_units_unless_raw_counts
  validate :enforce_units_on_raw_counts

  private

  # unset the value for :units unless :is_raw_counts is true
  # this has to be invoked as a validation as callbacks only fire on parent document (StudyFile)
  def unset_units_unless_raw_counts
    unless self.is_raw_counts
      self.units = nil
    end
  end

  # enforce selecting units on raw counts matrices
  def enforce_units_on_raw_counts
    if self.is_raw_counts && self.units.blank?
      errors.add(:units, ' must have a value for raw counts matrices')
    end
  end

end
