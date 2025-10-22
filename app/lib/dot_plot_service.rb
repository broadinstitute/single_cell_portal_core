# service that handles preprocessing expression/annotation data to speed up dot plot rendering
class DotPlotService
  # main handler for launching ingest job to process expression data into DotPlotGene objects
  # since the study can have only one processed matrix/metadata file, this will only run if the study is eligible
  #
  # * *params*
  #   - +study+ (Study) => the study that owns the data
  #   - +cluster_group+ (ClusterGroup) => the cluster to set associations for
  #   - +user+ (User) => the user that will run the job
  #
  # * *yields*
  #   - (IngestJob) => the job that will be run to process the data
  #
  # * *raises*
  #   - (ArgumentError) => study/cluster is not eligible, invalid parameters
  def self.run_process_dot_plot_genes(study, cluster_group, user)
    validate_study(study, cluster_group)
    expression_file = study_processed_matrices(study)&.first
    metadata_file = study.metadata_file
    validate_source_data(expression_file, metadata_file)
    params_object = create_params_object(cluster_group, expression_file, metadata_file)
    if params_object.valid?
      job = IngestJob.new(
        study:, study_file: expression_file, user:, action: :ingest_dot_plot_genes, params_object:
      )
      job.delay.push_remote_and_launch_ingest
      true
    else
      raise ArgumentError, "job parameters failed to validate: #{params_object.errors.full_messages.join(', ')}"
    end
  end

  # process all qualifying clusters/genes in a give study
  #
  # * *params*
  #   - +study+ (Study) => the study that owns the data
  #   - +user+ (User) => the user that will run the job
  #
  # * *yields*
  #   - (IngestJob) => the job that will be run to process the data
  def self.process_all_study_data(study, user)
    requested_user = user || study.user
    clusters = study.cluster_groups.reject { |cluster| cluster_processed?(study, cluster) }
    clusters.each do |cluster|
      run_process_dot_plot_genes(study, cluster, requested_user)
    end
  end

  # create DotPlotGeneIngestParameters object based on the provided files
  #
  # * *params*
  #   - +cluster_group+ (ClusterGroup) => the cluster group to associate with
  #   - +expression_file+ (StudyFile) => the expression matrix file to process
  #   - +metadata_file+ (StudyFile) => the metadata file to source annotations
  #
  # * *returns*
  #   - (DotPlotGeneIngestParameters) => a parameters object with the necessary file paths and metadata
  def self.create_params_object(cluster_group, expression_file, metadata_file)
    params = {
      cluster_group_id: cluster_group.id,
      cluster_file: RequestUtils.cluster_file_url(cluster_group)
    }
    case expression_file.file_type
    when 'Expression Matrix'
      params[:matrix_file_type] = 'dense'
      params[:matrix_file_path] = expression_file.gs_url
      params[:cell_metadata_file] = metadata_file.gs_url
    when 'MM Coordinate Matrix'
      params[:matrix_file_type] = 'mtx'
      genes_file = expression_file.bundled_files.detect { |f| f.file_type == '10X Genes File' }
      barcodes_file = expression_file.bundled_files.detect { |f| f.file_type == '10X Barcodes File' }
      params[:matrix_file_path] = expression_file.gs_url
      params[:cell_metadata_file] = metadata_file.gs_url
      params[:gene_file] = genes_file.gs_url
      params[:barcode_file] = barcodes_file.gs_url
    when 'AnnData'
      params[:matrix_file_type] = 'mtx' # extracted expression for AnnData is in MTX format
      params[:cell_metadata_file] = RequestUtils.data_fragment_url(metadata_file, 'metadata')
      params[:matrix_file_path] = RequestUtils.data_fragment_url(
        expression_file, 'matrix', file_type_detail: 'processed'
      )
      params[:gene_file] = RequestUtils.data_fragment_url(
        expression_file, 'features', file_type_detail: 'processed'
      )
      params[:barcode_file] = RequestUtils.data_fragment_url(
        expression_file, 'barcodes', file_type_detail: 'processed'
      )
    end
    DotPlotGeneIngestParameters.new(**params)
  end

  # determine study eligibility - can only have one processed matrix and be able to visualize clusters
  #
  # * *params*
  #   - +study+ (Study) => the study that owns the data
  # * *returns*
  #   - (Boolean) => true if the study is eligible for dot plot visualization
  def self.study_eligible?(study)
    processed_matrices = study_processed_matrices(study)
    study.can_visualize_clusters? && study.has_expression_data? && processed_matrices.size == 1
  end

  # check if the given study/cluster has already been preprocessed
  # * *params*
  #   - +study+ (Study) => the study that owns the data
  #   - +cluster_group+ (ClusterGroup) => the cluster to check for processed data
  #
  # * *returns*
  #   - (Boolean) => true if the study/cluster has already been processed
  def self.cluster_processed?(study, cluster_group)
    DotPlotGene.where(study:, cluster_group:).exists?
  end

  # get processed expression matrices for a study
  #
  # * *params*
  #   - +study+ (Study) => the study to get matrices for
  #
  # * *returns*
  #   - (Array<StudyFile>) => an array of processed expression matrices for the study
  def self.study_processed_matrices(study)
    study.expression_matrices.select do |matrix|
      matrix.is_viz_anndata? || !matrix.is_raw_counts_file?
    end
  end

  # validate the study for dot plot preprocessing
  #
  # * *params*
  #   - +study+ (Study) => the study to validate
  #
  # * *raises*
  #   - (ArgumentError) => if the study is invalid or does not qualify for dot plot visualization
  def self.validate_study(study, cluster_group)
    raise ArgumentError, 'Invalid study' unless study.present? && study.is_a?(Study)
    raise ArgumentError, 'Study does not qualify for dot plot visualization' unless study_eligible?(study)
    raise ArgumentError, 'Study has already been processed' if cluster_processed?(study, cluster_group)
  end

  # validate required data is present for processing
  #
  # * *params*
  #   - +expression_file+ (StudyFile) => the expression matrix file to process
  #   - +metadata_file+ (StudyFile) => the metadata file to source annotations
  #
  # * *raises*
  #   - (ArgumentError) => if the source data is not fully parsed or MTX bundled is not completed
  def self.validate_source_data(expression_file, metadata_file)
    raise ArgumentError, 'Missing required files' unless expression_file.present? && metadata_file.present?
    raise ArgumentError, 'Source data not fully parsed' unless expression_file.parsed? && metadata_file.parsed?
    raise ArgumentError, 'MTX bundled not completed' if expression_file.should_bundle? &&
                                                        !expression_file.has_completed_bundle?
  end
end
