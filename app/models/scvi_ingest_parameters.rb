class ScviIngestParameters
  include ActiveModel::Model
  include Parameterizable

  # accession: Study accession to run job in
  # docker_image: published GCR image of SCVI/SCANVI Docker image
  # machine_type: GCE machine type (must be n1 for GPU support)
  # atac_file: ATAC-seq AnnData file
  # gex_file: Gene expression AnnData file
  # ref_file: reference AnnData file for label transfer
  # localize: True to push/pull files from bucket
  # file_size: size of input file for machine scaling
  PARAM_DEFAULTS = {
    accession: nil,
    docker_image: 'us.gcr.io/broad-gotc-prod/scvi-scanvi:1.0.0-1.2-1760025671',
    machine_type: 'n1-highmem-8',
    atac_file: nil,
    gex_file: nil,
    ref_file: nil,
    localize: true
  }.freeze

  # values that are available as methods but not as attributes (and not passed to command line)
  NON_ATTRIBUTE_PARAMS = %i[accession machine_type docker_image].freeze

  attr_accessor(*PARAM_DEFAULTS.keys)

  validates :accession, presence: true
  validates :atac_file, :gex_file, :ref_file, presence: true, format: { with: Parameterizable::GS_URL_REGEXP }
  validates :machine_type, presence: true, format: /n1-highmem-\d/

  # get the particular file (either source AnnData or fragment) being processed by this job
  def associated_file
    atac_file || gex_file
  end
end
