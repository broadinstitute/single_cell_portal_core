# frozen_string_literal: true

# service that handles preprocessing expression/annotation data to speed up dot plot rendering
class DotPlotService

  # main handler for launching ingest job to process expression data
  #
  # * *params*
  #   - +study+ (Study) => the study that owns the data
  #   - +cluster_group+ (ClusterGroup) => the cluster to source cell names from
  #   - +annotation_file+ (StudyFile) => the StudyFile containing annotation data
  #   - +expression_file+ (StudyFile) => the StudyFile to source data from
  #
  # * *yields*
  #   - (IngestJob) => the job that will be run to process the data
  def self.run_preprocess_expression_job(study, cluster_group, annotation_file, expression_file)
    study_eligible?(study) # method stub, waiting for scp-ingest-pipeline implementation
  end

  # determine study eligibility - can only have one processed matrix and be able to visualize clusters
  #
  # * *params*
  #   - +study+ (Study) the study that owns the data
  # * *returns*
  #   - (Boolean) true if the study is eligible for dot plot visualization
  def self.study_eligible?(study)
    processed_matrices = study.expression_matrices.select do |matrix|
      matrix.is_viz_anndata? || !matrix.is_raw_counts_file?
    end
    study.can_visualize_clusters? && study.has_expression_data? && processed_matrices.size == 1
  end
end
