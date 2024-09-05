# class to hold parameters specific to differential expression jobs in PAPI
class DifferentialExpressionParameters
  include ActiveModel::Model
  include Parameterizable
  include ComputeScaling

  # name of Ingest Pipeline CLI parameter that invokes correct parser
  PARAMETER_NAME = '--differential-expression'.freeze

  # scaling coefficient for auto-selecting machine_type
  GB_PER_CORE = 3.5

  # annotation_name: name of annotation to use for DE
  # annotation_scope: scope of annotation (study, cluster)
  # annotation_file: source file for above annotation
  # cluster_file: clustering file with cells to use as control list for DE
  # cluster_name: name of associated ClusterGroup object
  # matrix_file_path: raw counts matrix with source expression data
  # matrix_file_type: type of raw counts matrix (dense, sparse)
  # gene_file (optional): genes/features file for sparse matrix
  # barcode_file (optional): barcodes file for sparse matrix
  # machine_type (optional): override for default ingest machine type (uses 'n2d-highmem-8')
  # file_size (optional): size of raw matrix for machine_type scaling (only needed for h5ad files)
  PARAM_DEFAULTS = {
    annotation_name: nil,
    annotation_type: 'group',
    annotation_scope: nil,
    annotation_file: nil,
    cluster_file: nil,
    cluster_name: nil,
    matrix_file_path: nil,
    matrix_file_type: nil,
    gene_file: nil,
    barcode_file: nil,
    machine_type: 'n2d-highmem-8',
    file_size: 0
  }.freeze

  # values that are available as methods but not as attributes (and not passed to command line)
  NON_ATTRIBUTE_PARAMS = %i[machine_type file_size].freeze

  attr_accessor(*PARAM_DEFAULTS.keys)

  validates :annotation_name, :annotation_scope, :annotation_file, :cluster_file,
            :cluster_name, :matrix_file_path, :matrix_file_type, presence: true
  validates :annotation_file, :cluster_file, :matrix_file_path,
            format: { with: Parameterizable::GS_URL_REGEXP, message: 'is not a valid GS url' }
  validates :annotation_scope, inclusion: %w[cluster study]
  validates :matrix_file_type, inclusion: %w[dense mtx h5ad]
  validates :machine_type, inclusion: Parameterizable::GCE_MACHINE_TYPES
  validates :gene_file, :barcode_file,
            presence: true,
            format: {
              with: Parameterizable::GS_URL_REGEXP,
              message: 'is not a valid GS url'
            },
            if: -> { matrix_file_type == 'mtx' }

  def initialize(attributes = nil)
    super

    # auto-scale machine type for AnnData files
    if @matrix_file_type == 'h5ad'
      self.machine_type = assign_machine_type
    end
  end
end
