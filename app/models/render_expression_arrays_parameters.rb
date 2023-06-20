class RenderExpressionArraysParameters
  include ActiveModel::Model
  include Parameterizable

  # stores mapping for small/medium/large images, based on matrix file size
  MACHINE_TYPES = {
    small: 'n1-highcpu-4',
    medium: 'n1-highcpu-32',
    large: 'n1-highcpu-96'
  }.freeze

  # name of Python parameter that invokes correct parser
  PARAMETER_NAME = '--render-expression-arrays'.freeze

  # cluster_file: clustering file with cells to use as control list for rendering expression arrays
  # cluster_name: name of associated ClusterGroup object
  # matrix_file_path: processed expression matrix with source expression data
  # matrix_file_type: type of processed matrix (dense, sparse)
  # gene_file (optional): genes/features file for sparse matrix
  # barcode_file (optional): barcodes file for sparse matrix
  PARAM_DEFAULTS = {
    cluster_file: nil,
    cluster_name: nil,
    matrix_file_path: nil,
    matrix_file_type: nil,
    gene_file: nil,
    barcode_file: nil
  }.freeze

  attr_accessor(*PARAM_DEFAULTS.keys)

  validates :cluster_file, :cluster_name, :matrix_file_path, :matrix_file_type, presence: true
  validates :cluster_file, :matrix_file_path,
            format: { with: Parameterizable::GS_URL_REGEXP, message: 'is not a valid GS url' }
  validates :matrix_file_type, inclusion: %w[dense mtx]
  validates :gene_file, :barcode_file,
            presence: true,
            format: {
              with: Parameterizable::GS_URL_REGEXP,
              message: 'is not a valid GS url'
            },
            if: -> { matrix_file_type == 'mtx' }

  # get the size of the source expression matrix
  # used for determining what size image to provision
  def matrix_size
    segments = matrix_file_path.split('/')
    bucket_id = segments[2]
    upload_file_name = segments.last
    study = Study.find_by(bucket_id:)
    study_file = StudyFile.find_by(study:, upload_file_name:)
    study_file.upload_file_size
  end

  # machine_type for PAPI jobs, varies depending on size of matrix
  def machine_type
    case matrix_size
    when 1..1.megabyte
      MACHINE_TYPES[:small]
    when 1.megabyte..1.gigabyte
      MACHINE_TYPES[:medium]
    else
      MACHINE_TYPES[:large]
    end
  end
end
