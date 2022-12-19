class ImagePipelineParameters
  include ActiveModel::Model
  include Parameterizable

  # accession: study accession
  # bucket: GCS bucket name
  # cluster: name of ClusterGroup object
  # environment: Rails environment
  # cores: number of cores to use in processing images (defaults to available cores - 1)
  # docker_image: image pipeline docker image to use
  # machine_type: GCE machine type, see Parameterizable::GOOGLE_VM_MACHINE_TYPES
  # data_cache_perftime: total runtime (in ms) of upstream :render_expression_arrays job
  attr_accessor :accession, :bucket, :cluster, :environment, :cores, :docker_image, :machine_type,
                :data_cache_perftime

  validates :accession, :bucket, :cluster, :environment, :cores, :data_cache_perftime, presence: true
  validates :machine_type, inclusion: Parameterizable::GCE_MACHINE_TYPES
  validates :environment, inclusion: %w[development test staging production]
  validates :docker_image, format: { with: Parameterizable::GCR_URI_REGEXP }
  validate :machine_has_cores?

  # default values for all jobs
  PARAM_DEFAULTS = {
    docker_image: 'gcr.io/broad-singlecellportal-staging/image-pipeline:0.1.0_e2992be5b',
    machine_type: 'n1-highcpu-96'
  }.freeze

  def initialize(attributes = {})
    super
    @environment ||= Rails.env.to_s
    @docker_image ||= PARAM_DEFAULTS[:docker_image]
    @machine_type ||= PARAM_DEFAULTS[:machine_type]
    @cores ||= machine_type_cores - 1
  end

  # available cores by machine_type
  def machine_type_cores
    machine_type.split('-').last.to_i
  end

  # default attributes hash
  def attributes
    {
      accession:, bucket:, cluster:, environment:, cores:
    }.with_indifferent_access
  end

  private

  # ensure requested cores supported by machine_type, reserving 1 for OS
  def machine_has_cores?
    if cores + 1 > machine_type_cores || cores < 1
      errors.add(:cores, "(#{cores}) not supported by machine_type: #{machine_type}")
    end
  end
end
