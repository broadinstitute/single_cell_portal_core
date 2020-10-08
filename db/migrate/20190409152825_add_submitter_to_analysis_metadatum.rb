class AddSubmitterToAnalysisMetadatum < Mongoid::Migration
  def self.up
    AnalysisMetadatum.all.each do |analysis|
      begin
        if analysis.study.present?
          puts "#{Time.zone.now} setting submitter on #{analysis.name}:#{analysis.submission_id}"
          study = analysis.study
          submission = ApplicationController.firecloud_client.get_workspace_submission(study.firecloud_project, study.firecloud_workspace,
                                                                       analysis.submission_id)
          submitter = submission['submitter']
          analysis.update(submitter: submitter)
          puts "#{Time.zone.now} submitter successfully set on #{analysis.name}:#{analysis.submission_id}"
        else
          puts "#{Time.zone.now} skipping #{analysis.name}:#{analysis.submission_id}, study no longer present"
        end
      rescue => e
        error_context = ErrorTracker.format_extra_context(analysis)
        ErrorTracker.report_exception(e, nil, error_context)
        puts "#{Time.zone.now} unable set submitter on #{analysis.name}:#{analysis.submission_id}; #{e.message}"
      end
    end
  end

  def self.down
    AnalysisMetadatum.update_all(submitter: nil)
  end
end
