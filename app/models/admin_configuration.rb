class AdminConfiguration

  ###
  #
  # AdminConfiguration: a generic object that is used to hold site-wide configuration options
  # Can only be accessed by user accounts that are configured as 'admins'
  #
  ###

  include Mongoid::Document
  field :config_type, type: String
  field :value_type, type: String
  field :multiplier, type: String
  field :value, type: String

  has_many :configuration_options, dependent: :destroy
  accepts_nested_attributes_for :configuration_options, allow_destroy: true

  FIRECLOUD_ACCESS_NAME = 'FireCloud Access'
  API_NOTIFIER_NAME = 'API Health Check Notifier'
  NUMERIC_VALS = %w(byte kilobyte megabyte terabyte petabyte exabyte)
  CONFIG_TYPES = ['Daily User Download Quota', 'Workflow Name', 'Portal FireCloud User Group',
                  'Reference Data Workspace', 'Read-Only Access Control', 'QA Dev Email', API_NOTIFIER_NAME]
  ALL_CONFIG_TYPES = CONFIG_TYPES.dup << FIRECLOUD_ACCESS_NAME
  VALUE_TYPES = %w(Numeric Boolean String)

  validates_uniqueness_of :config_type,
                          message: ": '%{value}' has already been set.  Please edit the corresponding entry to update.",
                          unless: proc {|attributes| attributes['config_type'] == 'Workflow Name'}

  validates_presence_of :config_type, :value_type, :value
  validates_inclusion_of :config_type, in: ALL_CONFIG_TYPES
  validates_inclusion_of :value_type, in: VALUE_TYPES
  validates_inclusion_of :multiplier, in: NUMERIC_VALS, allow_blank: true
  validates_format_of :value, with: ValidationTools::OBJECT_LABELS,
                      message: ValidationTools::OBJECT_LABELS_ERROR,
                      unless: proc {|attributes| attributes.config_type == 'QA Dev Email'} # allow '@' for this config

  validate :manage_readonly_access

  # really only used for IDs in the table...
  def url_safe_name
    self.config_type.downcase.gsub(/[^a-zA-Z0-9]+/, '-').chomp('-')
  end

  def self.current_firecloud_access
    status = AdminConfiguration.find_by(config_type: AdminConfiguration::FIRECLOUD_ACCESS_NAME)
    if status.nil?
      'on'
    else
      status.value
    end
  end

  def self.firecloud_access_enabled?
    status = AdminConfiguration.find_by(config_type: AdminConfiguration::FIRECLOUD_ACCESS_NAME)
    if status.nil?
      true
    else
      status.value == 'on'
    end
  end

  # display value formatted by type
  def display_value
    case self.value_type
      when 'Numeric'
        unless self.multiplier.nil? || self.multiplier.blank?
          "#{self.value} #{self.multiplier}(s) <span class='badge'>#{self.convert_value_by_type} bytes</span>"
        else
          self.value
        end
      when 'Boolean'
        self.value == '1' ? 'Yes' : 'No'
      else
        self.value
    end
  end

  # converter to return requested value as an instance of its value type
  # numerics will return an interger or float depending on value contents (also understands Rails shorthands for byte size increments)
  # booleans return true/false based on matching a variety of possible 'true' values
  # strings just return themselves
  def convert_value_by_type
    case self.value_type
      when 'Numeric'
        unless self.multiplier.nil? || self.multiplier.blank?
          val = self.value.include?('.') ? self.value.to_f : self.value.to_i
          return val.send(self.multiplier.to_sym)
        else
          return self.value.to_f
        end
      when 'Boolean'
        return self.value == '1'
      else
        return self.value
    end
  end

  # method that disables access by revoking permissions to studies directly in FireCloud
  def self.configure_firecloud_access(status)
    case status
      when 'readonly'
        @config_setting = 'READER'
      when 'off'
        @config_setting = 'NO ACCESS'
      else
        @config_setting = 'ERROR'
    end
    unless @config_setting == 'ERROR'
      Rails.logger.info "#{Time.zone.now}: setting access on all '#{FireCloudClient::COMPUTE_BLACKLIST.join(', ')}' studies to #{@config_setting}"
      # only use studies not queued for deletion; those have already had access revoked
      # also filter out studies not in default portal project - user-funded projects are exempt from access revocation
      Study.not_in(queued_for_deletion: true).where(:firecloud_project.in => FireCloudClient::COMPUTE_BLACKLIST).each do |study|
        Rails.logger.info "#{Time.zone.now}: begin revoking access to study: #{study.name}"
        # first remove share access (only shares with FireCloud access, i.e. non-reviewers)
        shares = study.study_shares.non_reviewers
        shares.each do |user|
          Rails.logger.info "#{Time.zone.now}: revoking share access for #{user}"
          revoke_share_acl = Study.firecloud_client.create_workspace_acl(user, @config_setting)
          Study.firecloud_client.update_workspace_acl(study.firecloud_project, study.firecloud_workspace, revoke_share_acl)
        end
        # last, remove study owner access (unless project owner)
        owner = study.user.email
        Rails.logger.info "#{Time.zone.now}: revoking owner access for #{owner}"
        revoke_owner_acl = Study.firecloud_client.create_workspace_acl(owner, @config_setting)
        Study.firecloud_client.update_workspace_acl(study.firecloud_project, study.firecloud_workspace, revoke_owner_acl)
        Rails.logger.info "#{Time.zone.now}: access revocation for #{study.name} complete"
      end
      Rails.logger.info "#{Time.zone.now}: all '#{FireCloudClient::COMPUTE_BLACKLIST.join(', ')}' study access set to #{@config_setting}"
    else
      Rails.logger.info "#{Time.zone.now}: invalid status setting: #{status}; aborting"
    end
  end

  # method that re-enables access by restoring permissions to studies directly in FireCloud
  def self.enable_firecloud_access
    Rails.logger.info "#{Time.zone.now}: restoring access to all '#{FireCloudClient::COMPUTE_BLACKLIST.join(', ')}' studies"
    # only use studies not queued for deletion; those have already had access revoked
    # also filter out studies not in default portal project - user-funded projects are exempt from access revocation
    Study.not_in(queued_for_deletion: true).where(:firecloud_project.in => FireCloudClient::COMPUTE_BLACKLIST).each do |study|
      Rails.logger.info "#{Time.zone.now}: begin restoring access to study: #{study.name}"
      # first re-enable share access (to all non-reviewers)
      shares = study.study_shares.where(:permission.nin => %w(Reviewer)).to_a
      shares.each do |share|
        user = share.email
        share_permission = StudyShare::FIRECLOUD_ACL_MAP[share.permission]
        can_share = share_permission === 'WRITER' ? true : false
        can_compute = Rails.env == 'production' ? false : share_permission === 'WRITER' ? true : false
        Rails.logger.info "#{Time.zone.now}: restoring #{share_permission} permission for #{user}"
        restore_share_acl = Study.firecloud_client.create_workspace_acl(user, share_permission, can_share, can_compute)
        Study.firecloud_client.update_workspace_acl(study.firecloud_project, study.firecloud_workspace, restore_share_acl)
      end
      # last, restore study owner access (unless project is owned by user)
      owner = study.user.email
      Rails.logger.info "#{Time.zone.now}: restoring WRITER access for #{owner}"
      # restore permissions, setting compute acls correctly (disabled in production for COMPUTE_BLACKLIST projects)
      restore_owner_acl = Study.firecloud_client.create_workspace_acl(owner, 'WRITER', true, Rails.env == 'production' ? false : true)
      Study.firecloud_client.update_workspace_acl(study.firecloud_project, study.firecloud_workspace, restore_owner_acl)
      Rails.logger.info "#{Time.zone.now}: access restoration for #{study.name} complete"
    end
    Rails.logger.info "#{Time.zone.now}: all '#{FireCloudClient::COMPUTE_BLACKLIST.join(', ')}' study access restored"
  end

  # sends an email to all site administrators on startup notifying them of portal restart
  def self.restart_notification
    current_time = Time.zone.now.to_s(:long)
    locked_jobs = Delayed::Job.where(:locked_by.nin => [nil]).count
    message = "<p>The Single Cell Portal was restarted at #{current_time}.</p><p>There are currently #{locked_jobs} jobs waiting to be restarted.</p>"
    SingleCellMailer.admin_notification('Portal restart', nil, message).deliver_now
  end

  # method to unlock all current delayed_jobs to allow them to be restarted
  def self.restart_locked_jobs
    # determine current processes and their pids
    job_count = 0
    pid_files = Dir.entries(Rails.root.join('tmp','pids')).delete_if {|p| p.start_with?('.')}
    pids = {}
    pid_files.each do |file|
      pids[file.chomp('.pid')] = File.open(Rails.root.join('tmp', 'pids', file)).read.strip
    end
    locked_jobs = Delayed::Job.where(:locked_by.nin => [nil]).to_a
    locked_jobs.each do |job|
      # grab worker number and pid
      worker, pid_str = job.locked_by.split.minmax
      pid = pid_str.split(':').last
      # check if current job worker has matching pid; if not, then the job is orphaned and should be unlocked
      unless pids[worker] == pid
        Rails.logger.info "#{Time.zone.now}: Restarting orphaned process #{job.id} initially queued on #{job.created_at.to_s(:long)}"
        job.update(locked_by: nil, locked_at: nil)
        job_count += 1
      end
    end
    job_count
  end

  # method to be called from cron to check the health status of the FireCloud API
  # This method no longer disables access as we now do realtime checks on routes that depend on certain services being up
  # 'local-off' mode can now be used to manually put the portal in read-only mode
  def self.check_api_health
    api_ok = Study.firecloud_client.api_available?

    if !api_ok
      current_status = Study.firecloud_client.api_status
      Rails.logger.error "#{Time.zone.now}: ALERT: FIRECLOUD API SERVICE INTERRUPTION -- current status: #{current_status}"
      SingleCellMailer.firecloud_api_notification(current_status).deliver_now
    end
  end

  # set/revoke readonly access on public workspaces for READ_ONLY_SERVICE_ACCOUNT
  def self.set_readonly_service_account_permissions(grant_access)
    if Study.read_only_firecloud_client.present? && Study.read_only_firecloud_client.registered?
      study_count = 0
      Study.where(queued_for_deletion: false).each do |study|
        study.set_readonly_access(grant_access, true) # pass true for 'manual_set' option to force change
        study_count += 1
      end
      [true, "Permissions successfully set on #{study_count} studies."]
    else
      [false, 'You have not enabled the read-only service account yet.  You must create and register a read-only service account first before continuing.']
    end
  end

  def self.find_or_create_ws_user_group!
    groups = Study.firecloud_client.get_user_groups
    ws_owner_group = groups.detect {|group| group['groupName'] == FireCloudClient::WS_OWNER_GROUP_NAME &&
        group['role'] == 'Admin'}
    # create group if not found
    if ws_owner_group.present?
      ws_owner_group
    else
      # create and return group
      Study.firecloud_client.create_user_group(FireCloudClient::WS_OWNER_GROUP_NAME)
      Study.firecloud_client.get_user_group(FireCloudClient::WS_OWNER_GROUP_NAME)
    end
  end

  # getter to return all configuration options as a hash
  def options
    opts = {}
    self.configuration_options.each do |option|
      opts.merge!({option.name.to_sym => option.value})
    end
    opts
  end

  private

  def validate_value_by_type
    case self.value_type
      when 'Numeric'
        unless self.value.to_f >= 0
          errors.add(:value, 'must be greater than or equal to zero.  Please enter another value.')
        end
      else
        # for booleans, we use a select box so values are constrained.  for strings, any value is valid
        return true
    end
  end

  # grant/revoke access on setting change, will raise error if readonly account is not instantiated
  def manage_readonly_access
    if self.config_type == 'Read-Only Access Control'
      if Study.read_only_firecloud_client.present?
        if self.value_changed?
          AdminConfiguration.set_readonly_service_account_permissions(self.convert_value_by_type)
        end
      else
        errors.add(:config_type, '- You have not enabled the read-only service account yet.  You must enable this account first before continuing.  Please see https://github.com/broadinstitute/single_cell_portal_core#running-the-container#read-only-service-account for more information.')
      end
    end
  end
end

