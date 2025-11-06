class BackfillAnalysisSubmissions < Mongoid::Migration
  # def self.up
  #   AnalysisMetadatum.all.each do |analysis|
  #     study = analysis.study
  #     puts "Creating Analysis Submission for #{study.firecloud_project}/#{study.firecloud_workspace}:#{analysis.submission_id}"
  #     begin
  #       AnalysisSubmission.initialize_from_submission(study, analysis.submission_id)
  #       puts "Analysis Submission for #{study.firecloud_project}/#{study.firecloud_workspace}:#{analysis.submission_id} created"
  #     rescue => e
  #       # usually, the most common error is configuration we need has been deleted resulting in a 404
  #       put "Skipping submission #{analysis.submission_id} due to error: #{e.message}"
  #     end
  #   end
  # end
  #
  # def self.down
  #   AnalysisSubmission.delete_all
  # end
end
