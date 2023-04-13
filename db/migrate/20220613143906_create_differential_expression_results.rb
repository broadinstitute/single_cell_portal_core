class CreateDifferentialExpressionResults < Mongoid::Migration
  # validate DE results and determine which files to keep, if any
  def self.check_de_results(results_obj)
    de_identifier = "#{results_obj.study.accession}:#{results_obj.cluster_name} (#{results_obj.annotation_identifier})"
    Rails.logger.info "Checking DE results for #{de_identifier}"
    annotation = results_obj.annotation_object
    source_labels = annotation.respond_to?(:values) ? annotation.values : annotation[:values]
    if results_obj.valid?
      Rails.logger.info "Results for #{de_identifier} valid, saving"
      results_obj.save!
      Rails.logger.info "Save complete, keeping valid outputs for #{results_obj.one_vs_rest_comparisons.join(', ')}"
      # determine if there are some output files that are still invalid and should be removed
      # can be determined with the difference between the list of original values and observed values
      invalid_labels = source_labels - results_obj.one_vs_rest_comparisons
      Rails.logger.info "Found #{invalid_labels.count} invalid outputs: #{invalid_labels.join(', ')}"
      invalid_labels.each do |label|
        remove_output_file(results_obj, label)
      end
    else
      Rails.logger.info "Results for #{de_identifier} invalid, removing outputs from bucket"
      # clean up any output files in the bucket
      source_labels.each do |label|
        remove_output_file(results_obj, label)
      end
      results_obj.delete # remove object as it is invalid
    end
  end

  # remove a given DE result file from a study bucket, if present
  def self.remove_output_file(results_obj, label)
    begin
      output_location = results_obj.bucket_path_for(label)
      remote = ApplicationController.firecloud_client.get_workspace_file(results_obj.study.bucket_id, output_location)
      if remote.present?
        remote.delete
        Rails.logger.info "Removed output file at #{output_location}"
      else
        Rails.logger.error "Output file not found at #{output_location}"
      end
    rescue => e
      Rails.logger.error "Unable to remove possible DE output '#{output_location}' - #{e.message}"
      ErrorTracker.report_exception(e, nil, results_obj, { output_location: output_location })
    end
  end

  def self.up
    CellMetadatum.where(is_differential_expression_enabled: true).each do |metadata|
      study = metadata.study
      study.cluster_groups.each do |cluster_group|
        de_result = DifferentialExpressionResult.new(
          cluster_group: cluster_group, study: study, cluster_name: cluster_group.name,
          annotation_name: metadata.name, annotation_scope: 'study'
        )
        check_de_results(de_result)
      end
    end
    ClusterGroup.where(:cell_annotations.ne => []).each do |cluster_group|
      cluster_group.cell_annotations.each do |annotation|
        safe_annotation = annotation.with_indifferent_access
        next if !safe_annotation[:is_differential_expression_enabled]

        study = cluster_group.study
        de_result = DifferentialExpressionResult.new(
          cluster_group: cluster_group, study: study, cluster_name: cluster_group.name,
          annotation_name: safe_annotation[:name], annotation_scope: 'cluster'
        )
        check_de_results(de_result)
      end
    end
  end

  def self.down
    DifferentialExpressionResult.delete_all
  end
end
