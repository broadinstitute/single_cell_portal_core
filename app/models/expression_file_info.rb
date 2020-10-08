class ExpressionFileInfo
  include Mongoid::Document

  embedded_in :study_file

  field :library_construction_protocol, type: String
  field :units, type: String
  field :biosample_input_type, type: String
  field :multimodality, type: String
  field :is_raw_counts, type: Boolean, default: false

  # note that species and reference genome/annotation live at the study_file level, not here

  UNITS_VALUES = [nil, 'UMI-corrected raw counts', 'raw counts']
  validates :units, inclusion: {in: UNITS_VALUES}

  BIOSAMPLE_INPUT_TYPE_VALUES = [nil, 'whole cell', 'single nuclei', 'bulk']
  validates :biosample_input_type, inclusion: {in: BIOSAMPLE_INPUT_TYPE_VALUES}

  MULTIMODALITY_VALUES = [nil, 'CITE-seq', 'Patch-seq']
  validates :multimodality, inclusion: {in: MULTIMODALITY_VALUES}

  LIBRARY_CONSTRUCTION_VALUES = [nil,
                                 'Smart-seq2/Fluidigm C1',
                                 'MARS-seq',
                                 'Seq-Well v1',
                                 'Seq-Well S^3',
                                 'inDrop',
                                 'sci-RNA-seq',
                                 '10x 3\' v1',
                                 '10x 3\' v2',
                                 '10x 3\' v3',
                                 '10x 5\' v2',
                                 '10x 5\' v3',
                                 'CEL-seq2',
                                 'Drop-seq',
                                 'SCRB-seq',
                                 'ATAC-seq',
                                 'ChIP-seq',
                                 'methylomics']
  validates :library_construction_protocol, inclusion: {in: LIBRARY_CONSTRUCTION_VALUES}
end
