# handles launching jobs related to image pipeline
class ImagePipelineService
  # map of parameter names to StudyFile types
  FILE_TYPES_BY_PARAM = {
    cluster_file: ['Cluster'],
    matrix_file: ['Expression Matrix', 'MM Coordinate Matrix']
  }.freeze

  # launch a job to generate cache of static images using array artifacts generated from
  # :run_render_expression_arrays_job
  #
  # * *params*
  #   - +study+                (Study) => study to generate images in
  #   - +cluster_file+         (StudyFile) => clustering file to use as source for cell names
  #   - +user+                 (User) => associated user (for email notifications)
  #   - +data_cache_perftime+ (Integer) => runtime of :render_expression_arrays job, for reporting
  #
  # * *yields*
  #   - (IngestJob) => image_pipeline job in PAPI
  #
  # * *returns*
  #   - (Boolean) => True if job queues successfully
  #
  # * *raises*
  #   - (ArgumentError) => if requested parameters do not validate
  def self.run_image_pipeline_job(study, cluster_file, user: nil, data_cache_perftime:)
    validate_study(study)
    requested_user = user || study.user
    params_object = create_image_pipeline_parameters_object(study, cluster_file, data_cache_perftime)
    submit_job(study:, cluster_file:, requested_user:, params_object:)
  end

  # launch a job to generate expression array artifacts to be used downstream by image pipeline
  #
  # * *params*
  #   - +study+        (Study) => study to generate data in
  #   - +cluster_file+ (StudyFile) => clustering file to use as source for cell names
  #   - +matrix_file+  (StudyFile) => processed expression matrix to use as source for expression values
  #   - +user+         (User) => associated user (for email notifications)
  #
  # * *yields*
  #   - (IngestJob) => render_expression_arrays job in PAPI
  #
  # * *returns*
  #   - (Boolean) => True if job queues successfully
  #
  # * *raises*
  #   - (ArgumentError) => if requested parameters do not validate
  def self.run_render_expression_arrays_job(study, cluster_file, matrix_file, user: nil)
    validate_study(study)
    requested_user = user || study.user
    params_object = create_expression_parameters_object(cluster_file, matrix_file)
    submit_job(study:, cluster_file:, requested_user:, params_object:)
  end

  # generic job submission handler
  #
  # * *params*
  #   - +study+          (Study) => study to launch job for
  #   - +cluster_file+   (StudyFile) => clustering file to use as source for cell names
  #   - +requested_user+ (User) => associated user (for email notifications)
  #   - +params_object+  (ImagePipelineParameters, RenderExpressionArrayParameters) => parameters object
  #
  # * *yields*
  #   - (IngestJob) => render_expression_arrays job in PAPI
  #
  # * *returns*
  #   - (Boolean) => True if job queues successfully
  #
  # * *raises*
  #   - (ArgumentError) => if requested parameters do not validate
  def self.submit_job(study:, cluster_file:, requested_user:, params_object:)
    if params_object.valid?
      job = IngestJob.new(study: study, study_file: cluster_file, user: requested_user,
                          action: params_object.action_name, params_object: params_object)
      job.delay.push_remote_and_launch_ingest
      true
    else
      raise ArgumentError,
            "#{params_object.action_name} job parameters failed to validate: #{params_object.errors.full_messages}"
    end
  end

  # create a RenderExpressionArraysParameters object to pass to IngestJob
  #
  # * *params*
  #   - +cluster_file+ (StudyFile) => clustering file to use as source for cell names
  #   - +matrix_file+  (StudyFile) => processed expression matrix to use as source for expression values
  #
  # * *returns*
  #   - (RenderExpressionArraysParameters) => parameters object
  #
  # * *raises*
  #   - (ArgumentError) => if requested parameters do not validate
  def self.create_expression_parameters_object(cluster_file, matrix_file)
    # Ruby 3.1 Hash literal syntax sugar!
    { cluster_file:, matrix_file: }.each do |param_name, study_file|
      validate_study_file(study_file, param_name)
    end
    parameters = {
      cluster_file: cluster_file.gs_url,
      cluster_name: cluster_file.name,
      matrix_file_path: matrix_file.gs_url
    }
    case matrix_file.file_type
    when 'Expression Matrix'
      parameters[:matrix_file_type] = 'dense'
    when 'MM Coordinate Matrix'
      parameters[:matrix_file_type] = 'mtx'
      bundle = matrix_file.study_file_bundle
      parameters[:gene_file] = bundle.bundled_file_by_type('10X Genes File').gs_url
      parameters[:barcode_file] = bundle.bundled_file_by_type('10X Barcodes File').gs_url
    else
      raise ArgumentError, "invalid matrix_type: #{matrix_file.file_type}"
    end
    RenderExpressionArraysParameters.new(parameters)
  end

  # create a ImagePipelineParameters object to pass to IngestJob
  #
  # * *params*
  #   - +study+                (Study) => study to generate images in
  #   - +cluster_file+         (StudyFile) => clustering file to use as source for cell names
  #   - +data_cache_perftime+ (Integer) => runtime of :render_expression_arrays job, for reporting
  #
  # * *returns*
  #   - (ImagePipelineParameters) => parameters object
  #
  # * *raises*
  #   - (ArgumentError) => if requested parameters do not validate
  def self.create_image_pipeline_parameters_object(study, cluster_file, data_cache_perftime)
    validate_study_file(cluster_file, :cluster_file)
    cluster_name = ClusterGroup.find_by(study: study, study_file: cluster_file)&.name
    ImagePipelineParameters.new(
      accession: study.accession, bucket: study.bucket_id, cluster: cluster_name, data_cache_perftime:
    )
  end

  # validate a study is a candidate for image pipeline jobs
  #
  # * *params*
  #   - +study+ (Study) => study to validate, must be public and have clustering/expression data
  #
  # * *raises*
  #   - (ArgumentError) => if study does not meet requirements
  def self.validate_study(study)
    raise ArgumentError, 'invalid study, must be public' unless study.is_a?(Study) && study.public
    raise ArgumentError, 'study does not have clustering data' unless study.has_cluster_data?
    raise ArgumentError, 'study does not have expression data' unless study.has_expression_data?
  end

  # validate a study file for use in render_expression_arrays
  # must be a StudyFile instance that has been pushed to the workspace bucket (does not need to be parsed)
  # MM Coordinate Matrix files must also have completed bundle (genes/barcodes files)
  #
  # * *params*
  #   - +study_file+  (StudyFile) => study file to validate
  #   - +param_name+  (String, Symbol) => name of parameter being validated
  #
  # * *raises*
  #   - (ArgumentError) => if study file does not validate
  def self.validate_study_file(study_file, param_name)
    raise ArgumentError, "invalid file for #{param_name}: #{study_file.class.name}" unless study_file.is_a?(StudyFile)
    unless FILE_TYPES_BY_PARAM[param_name].include?(study_file.file_type)
      raise ArgumentError, "invalid file_type for #{param_name}: #{study_file.file_type}"
    end
    raise ArgumentError, "#{param_name}:#{study_file.upload_file_name} not in bucket" unless file_in_bucket?(study_file)

    if study_file.is_expression? && study_file.should_bundle? && !study_file.has_completed_bundle?
      raise ArgumentError, "matrix #{study_file.name} missing completed bundle"
    end
  end

  # check if a requested file is in the workspace bucket
  #
  # * *params*
  #   - +study_file+ (StudyFile) => study file to check bucket for
  #
  # * *returns*
  #   - (Boolean) => T/F if file is present in bucket
  def self.file_in_bucket?(study_file)
    ApplicationController.firecloud_client.workspace_file_exists?(
      study_file.study.bucket_id, study_file.bucket_location
    )
  end
end
