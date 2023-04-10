# class to hold parameters specific to differential expression jobs in PAPI
class DifferentialExpressionParameters
  include ActiveModel::Model
  include Parameterizable

  # name of Ingest Pipeline CLI parameter that invokes correct parser
  PARAMETER_NAME = '--differential-expression'.freeze

  # annotation_name: name of annotation to use for DE
  # annotation_scope: scope of annotation (study, cluster)
  # annotation_file: source file for above annotation
  # cluster_file: clustering file with cells to use as control list for DE
  # cluster_name: name of associated ClusterGroup object
  # matrix_file_path: raw counts matrix with source expression data
  # matrix_file_type: type of raw counts matrix (dense, sparse)
  # gene_file (optional): genes/features file for sparse matrix
  # barcode_file (optional): barcodes file for sparse matrix
  # machine_type (optional): override for default ingest machine type (uses 'n1-highmem-8')
  attr_accessor :annotation_name, :annotation_scope, :annotation_file, :cluster_file, :cluster_name, :matrix_file_path,
                :matrix_file_type, :gene_file, :barcode_file, :machine_type

  validates :annotation_name, :annotation_scope, :annotation_file, :cluster_file,
            :cluster_name, :matrix_file_path, :matrix_file_type, presence: true
  validates :annotation_file, :cluster_file, :matrix_file_path,
            format: { with: Parameterizable::GS_URL_REGEXP, message: 'is not a valid GS url' }
  validates :annotation_scope, inclusion: %w[cluster study]
  validates :matrix_file_type, inclusion: %w[dense mtx]
  validates :machine_type, inclusion: Parameterizable::GCE_MACHINE_TYPES
  validates :gene_file, :barcode_file,
            presence: true,
            format: {
              with: Parameterizable::GS_URL_REGEXP,
              message: 'is not a valid GS url'
            },
            if: -> { matrix_file_type == 'mtx' }

  # apply default value for :machine_type, unless overridden
  def initialize(attributes = {})
    super
    @machine_type ||= 'n1-highmem-8'
  end

  # default attributes hash
  def attributes
    {
      annotation_name: annotation_name,
      annotation_type: 'group',
      annotation_scope: annotation_scope,
      annotation_file: annotation_file,
      cluster_file: cluster_file,
      cluster_name: cluster_name,
      matrix_file_path: matrix_file_path,
      matrix_file_type: matrix_file_type,
      gene_file: gene_file,
      barcode_file: barcode_file
    }.with_indifferent_access
  end
end
