# frozen_string_literal: true

# class to hold parameters specific to ingest job for computing dot plot gene metrics
class DotPlotGeneIngestParameters
  include ActiveModel::Model
  include Parameterizable

  # cell_metadata_file: metadata file to source annotations
  # cluster_file: clustering file with cells to use as control list for filtering and optional annotations
  # cluster_group_id: BSON ID of ClusterGroup object for associations
  # matrix_file_path: expression matrix with source data
  # matrix_file_type: type of expression matrix (dense, sparse)
  # gene_file (optional): genes/features file for sparse matrix
  # barcode_file (optional): barcodes file for sparse matrix
  # machine_type (optional): override for default ingest machine type (uses 'n2d-highmem-8')
  PARAM_DEFAULTS = {
    cell_metadata_file: nil,
    cluster_file: nil,
    cluster_group_id: nil,
    matrix_file_path: nil,
    matrix_file_type: nil,
    gene_file: nil,
    barcode_file: nil,
    machine_type: 'n2d-highmem-8'
  }.freeze

  # values that are available as methods but not as attributes (and not passed to command line)
  NON_ATTRIBUTE_PARAMS = %i[machine_type].freeze

  attr_accessor(*PARAM_DEFAULTS.keys)

  validates :cell_metadata_file, :cluster_file, :cluster_group_id, :matrix_file_path, :matrix_file_type, presence: true
  validates :cell_metadata_file, :cluster_file, :matrix_file_path,
            format: { with: Parameterizable::GS_URL_REGEXP, message: 'is not a valid GS url' }
  validates :matrix_file_type, inclusion: %w[dense mtx]
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
  end

  def cluster_group
    ClusterGroup.find(cluster_group_id)
  end
end
