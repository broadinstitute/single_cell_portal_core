# methods related to terra workflow analyses
# corresponding to the 'analysis' tab in study overview
class TerraAnalysisService

  def self.list_submissions(study)
    # load list of previous submissions
    workspace = ApplicationController.firecloud_client.get_workspace(study.firecloud_project, study.firecloud_workspace)
    submissions = ApplicationController.firecloud_client.get_workspace_submissions(study.firecloud_project, study.firecloud_workspace)

    submissions.each do |submission|
      update_analysis_submission(submission)
    end
    # remove deleted submissions from list of runs
    if !workspace['workspace']['attributes']['deleted_submissions'].blank?
      deleted_submissions = workspace['workspace']['attributes']['deleted_submissions']['items']
      submissions.delete_if {|submission| deleted_submissions.include?(submission['submissionId'])}
    end
    submissions
  end

  # update AnalysisSubmissions when loading study analysis tab
  # will not backfill existing workflows to keep our submission history clean
  def self.update_analysis_submission(submission)
    analysis_submission = AnalysisSubmission.find_by(submission_id: submission['submissionId'])
    if analysis_submission.present?
      workflow_status = submission['workflowStatuses'].keys.first # this only works for single-workflow analyses
      analysis_submission.update(status: workflow_status)
      analysis_submission.delay.set_completed_on # run in background to avoid UI blocking
    end
  end

  # check if a user can run workflows on the given study
  def self.user_can_compute?(study, user)
    if user.nil? || !user.registered_for_firecloud?
      return false
    end

    begin
      workspace_acl = ApplicationController.firecloud_client.get_workspace_acl(study.firecloud_project, study.firecloud_workspace)
      if workspace_acl['acl'][user.email].nil?
        # check if user has project-level permissions
        user.is_billing_project_owner?(study.firecloud_project)
      else
        workspace_acl['acl'][user.email]['canCompute']
      end
    rescue => e
      ErrorTracker.report_exception(e, user, { study: study.attributes.to_h.except('description')})
      Rails.logger.error "Unable to retrieve compute permissions for #{user.email}: #{e.message}"
      false
    end
  end
end
