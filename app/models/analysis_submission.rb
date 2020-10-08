class AnalysisSubmission
  include Mongoid::Document

  field :submission_id, type: String
  field :submitter, type: String
  field :analysis_name, type: String
  field :status, type: String
  field :firecloud_project, type: String
  field :firecloud_workspace, type: String
  field :submitted_on, type: DateTime
  field :completed_on, type: DateTime
  field :submitted_from_portal, type: Boolean, default: true

  belongs_to :study, optional: true

  SUBMISSON_STATUSES = %w(Queued Launching Submitted Running Failed Succeeded Aborting Aborted Unknown Deleted).freeze
  COMPLETION_STATUSES = %w(Aborted Succeeded Failed Deleted)
  validates_presence_of :submission_id, :submitter, :analysis_name, :firecloud_project, :firecloud_workspace
  validates_inclusion_of :status, in: SUBMISSON_STATUSES, if: proc {|attributes| attributes.status.present?}
  validates_uniqueness_of :submission_id

  # cron job to run weekly that will update the status of any 'in-process' analysis submissions
  def self.update_running_submissions
    self.where(:status.nin => COMPLETION_STATUSES).each do |submission|
      begin
        if submission.study.present?
          workspace_submission = submission.get_submission_json
          last_workflow = submission.get_last_workflow(workspace_submission['workflows'])
          latest_status = last_workflow['status']
          completion_time = DateTime.parse(last_workflow['statusLastChangedDate']).in_time_zone
          if COMPLETION_STATUSES.include?(latest_status)
            Rails.logger.info "Setting #{submission.firecloud_project}/#{submission.firecloud_workspace}:#{submission.submission_id} to '#{latest_status}'"
            submission.update(status: latest_status, completed_on: completion_time)
          end
        else
          Rails.logger.info "Setting #{submission.firecloud_project}/#{submission.firecloud_workspace}:#{submission.submission_id} to 'Deleted' as study was deleted"
          submission.update(status: 'Deleted', completed_on: Time.zone.now)
        end
      rescue => e
        error_context = ErrorTracker.format_extra_context(submission)
        ErrorTracker.report_exception(e, ApplicationController.firecloud_client.issuer, error_context)
        Rails.logger.error "Setting #{submission.firecloud_project}/#{submission.firecloud_workspace}:#{submission.submission_id} to 'Deleted' due to error: #{e.message}"
        submission.update(status: 'Deleted', completed_on: Time.zone.now)
      end
    end
  end

  # initialize a new AnalysisSubmission record from the FireCloud API JSON entry
  # only to be used to backfill existing submissions
  def self.initialize_from_submission(study, submission_id)
    analysis_submission = AnalysisSubmission.new(study_id: study.id, firecloud_project: study.firecloud_project,
                                                 firecloud_workspace: study.firecloud_workspace, submission_id: submission_id)
    submission = analysis_submission.get_submission_json
    analysis_submission.submitter = submission['submitter']
    analysis_submission.submission_id = submission['submissionId']
    last_workflow = self.get_last_workflow(submission['workflows'])
    analysis_submission.status = last_workflow['status']
    analysis_submission.submitted_on = DateTime.parse(submission['submissionDate']).in_time_zone
    analysis_method_name = analysis_submission.get_analysis_name_from_config(submission)
    analysis_submission.analysis_name = analysis_method_name
    if COMPLETION_STATUSES.include?(analysis_submission.status)
      completion_time = DateTime.parse(last_workflow['statusLastChangedDate']).in_time_zone
      analysis_submission.completed_on = completion_time
    end
    analysis_submission.save
  end

  # get user instance for submitter
  def user
    User.find_by(email: self.submitter)
  end

  # helper to get submission JSON from workspace
  def get_submission_json
    begin
      ApplicationController.firecloud_client.get_workspace_submission(self.firecloud_project, self.firecloud_workspace, self.submission_id)
    rescue => e
      error_context = ErrorTracker.format_extra_context(self)
      ErrorTracker.report_exception(e, self.user, error_context)
      logger.error "Unable to retrieve submission JSON for #{self.firecloud_project}/#{self.firecloud_workspace}:#{self.submission_id}; #{e.message}"
    end
  end

  # get the analysis name from the configuration used to submit this analysis
  def get_analysis_name_from_config(submission)
    begin
      configuration_namespace = submission['methodConfigurationNamespace']
      configuration_name = submission['methodConfigurationName']
      configuration = ApplicationController.firecloud_client.get_workspace_configuration(self.firecloud_project, self.firecloud_workspace,
                                                                  configuration_namespace, configuration_name)
      method = configuration['methodRepoMethod']
      "#{method['methodNamespace']}/#{method['methodName']}/#{method['methodVersion']}"
    rescue => e
      error_context = ErrorTracker.format_extra_context(self)
      ErrorTracker.report_exception(e, self.user, error_context)
      logger.error "Unable to retrieve submission configuration JSON for #{self.firecloud_project}/#{self.firecloud_workspace}:#{self.submission_id}; #{e.message}"
    end
  end

  # set the completion date based on current status
  def set_completed_on
    if COMPLETION_STATUSES.include?(self.status) && self.completed_on.blank?
      submission = self.get_submission_json
      last_workflow = self.get_last_workflow(submission['workflows'])
      if submission.present?
        completion_time = DateTime.parse(last_workflow['statusLastChangedDate']).in_time_zone
        self.update(completed_on: completion_time)
      end
    end
  end

  # get the latest workflow based on latest update timestamp
  def get_last_workflow(workflows)
    workflows.sort_by {|w| w['statusLastChangedDate']}.last
  end
end
