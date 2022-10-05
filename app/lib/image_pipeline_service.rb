# handles launching jobs related to image pipeline
class ImagePipelineService
  # launch a job to generate expression array artifacts to be used downstream by image pipeline
  #
  # * *params*
  #   - +study+ (Study) => study to generate data in
  #   - +cluster_file+ (StudyFile) => clustering file to use as source for cell names
  #   - +matrix_file+ (StudyFile) => processed expression matrix to use as source for expression values
  #   - +user+ (User) => associated user (for email notifications)
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
    raise ArgumentError, 'invalid study' unless study.is_a?(Study)

    requested_user = user || study.user
    params_object = create_expression_parameters_object(cluster_file, matrix_file)
    if params_object.valid?
      job = IngestJob.new(study: study, study_file: cluster_file, user: requested_user,
                          action: :render_expression_arrays, params_object: params_object)
      job.delay.push_remote_and_launch_ingest
      true
    else
      raise ArgumentError, "job parameters failed to validate: #{params_object.errors.full_messages}"
    end
  end

  # create a RenderExpressionArraysParameters object to pass to IngestJob
  #
  # * *params*
  #   - +cluster_file+ (StudyFile) => clustering file to use as source for cell names
  #   - +matrix_file+ (StudyFile) => processed expression matrix to use as source for expression values
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

  # validate a study file for use in render_expression_arrays
  # must be a StudyFile instance that has been pushed to the workspace bucket (does not need to be parsed)
  # MM Coordinate Matrix files must also have completed bundle (genes/barcodes files)
  #
  # * *params*
  #   - +study_file+ (StudyFile) => study file to validate
  #   - +param_name+ (String, Symbol) => name of parameter being validated
  #
  # * *raises*
  #   - (ArgumentError) => if study file does not validate
  def self.validate_study_file(study_file, param_name)
    raise ArgumentError, "invalid file for #{param_name}: #{study_file.class.name}" unless study_file.is_a?(StudyFile)
    raise ArgumentError, "#{param_name}:#{study_file.upload_file_name} not in bucket" unless file_in_bucket?(study_file)

    if study_file.is_expression? && study_file.should_bundle? && !matrix_file.has_completed_bundle?
      raise ArgumentError, "matrix #{matrix_file.name} missing completed bundle"
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