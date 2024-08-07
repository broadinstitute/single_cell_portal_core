class SubsampleAnnDataFiles < Mongoid::Migration
  def self.up
    anndata_files = StudyFile.where(file_type: 'AnnData', 'ann_data_file_info.reference_file' => false).pluck(:id)
    clusters = ClusterGroup.where(:study_file_id.in => anndata_files, :points.gte => 1000, subsampled: false)
    clusters.each do |cluster|
      study = cluster.study
      study_file = cluster.study_file
      user = study.user
      metadata_parsed = study.metadata_file.present? && study.metadata_file.parsed?
      if metadata_parsed && cluster.can_subsample? && !cluster.is_subsampling?
        job_identifier = "#{study_file.bucket_location}:#{study_file.id} (#{cluster.name})"
        cluster.update(is_subsampling: true)
        fragment = study_file.ann_data_file_info.find_fragment(
          data_type: :cluster, name: cluster.name
        ).with_indifferent_access
        cluster_file = RequestUtils.data_fragment_url(
          study_file, 'cluster', file_type_detail: fragment[:obsm_key_name]
        )
        cell_metadata_file = RequestUtils.data_fragment_url(study_file, 'metadata')
        subsample_params = AnnDataIngestParameters.new(
          subsample: true, ingest_anndata: false, extract: nil, obsm_keys: nil, name: cluster.name,
          cluster_file:, cell_metadata_file:
        )
        Rails.logger.info "Launching subsampling ingest run for #{job_identifier} via migration"
        submission = ApplicationController.life_sciences_api_client.run_pipeline(
          study_file:, user:, action: :ingest_subsample, params_object: subsample_params
        )
        job = IngestJob.new(
          pipeline_name: submission.name, study:, study_file:, user:, action: :ingest_subsample,
          params_object: subsample_params, reparse: false, persist_on_fail: true
        )
        job.delay.poll_for_completion
      end
    end
  end

  def self.down
    anndata_files = StudyFile.where(file_type: 'AnnData', 'ann_data_file_info.reference_file' => false).pluck(:id)
    clusters = ClusterGroup.where(:study_file_id.in => anndata_files, :points.gte => 1000, subsampled: true)
    clusters.each do |cluster|
      cluster.find_subsampled_data_arrays.delete_all
      cluster.update(subsampled: false)
    end
  end
end
