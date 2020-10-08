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
  INGEST_DOCKER_NAME = 'Ingest Pipeline Docker Image'
  NUMERIC_VALS = %w(byte kilobyte megabyte terabyte petabyte exabyte)
  CONFIG_TYPES = [INGEST_DOCKER_NAME, 'Daily User Download Quota', 'Portal FireCloud User Group',
                  'Reference Data Workspace', 'Read-Only Access Control', 'QA Dev Email', API_NOTIFIER_NAME]
  ALL_CONFIG_TYPES = CONFIG_TYPES.dup << FIRECLOUD_ACCESS_NAME
  VALUE_TYPES = %w(Numeric Boolean String)

  validates_uniqueness_of :config_type,
                          message: ": '%{value}' has already been set.  Please edit the corresponding entry to update."

  validates_presence_of :config_type, :value_type, :value
  validates_inclusion_of :config_type, in: ALL_CONFIG_TYPES
  validates_inclusion_of :value_type, in: VALUE_TYPES
  validates_inclusion_of :multiplier, in: NUMERIC_VALS, allow_blank: true
  validates_format_of :value, with: ValidationTools::OBJECT_LABELS,
                      message: ValidationTools::OBJECT_LABELS_ERROR,
                      unless: proc {|attributes| attributes.config_type == 'QA Dev Email'} # allow '@' for this config

  validate :manage_readonly_access
  validate :ensure_docker_image_present, if: proc {|attributes| attributes.config_type == INGEST_DOCKER_NAME}
  before_validation :strip_whitespace, if: proc {|attributes| attributes.value_type == 'String'}

  # really only used for IDs in the table...
  def url_safe_name
    self.config_type.downcase.gsub(/[^a-zA-Z0-9]+/, '-').chomp('-')
  end

  # Ingest docker image configuration getter
  def self.get_ingest_docker_image_config
    AdminConfiguration.find_by(config_type: AdminConfiguration::INGEST_DOCKER_NAME)
  end

  # Ingest docker image getter
  def self.get_ingest_docker_image
    ingest_config = self.get_ingest_docker_image_config
    if Rails.env != 'production' && ingest_config.present?
      ingest_config.value
    else
      Rails.application.config.ingest_docker_image
    end
  end

  # retrieve attributes from ingest docker image string
  # example return: {registry: 'gcr.io', project: 'broad-singlecellportal-staging', image_name: 'scp-ingest-pipeline', tag: '1.5.7'}
  def self.get_ingest_docker_image_attributes(image_name: self.get_ingest_docker_image)
    image_attributes = image_name.split('/')
    image_name, image_tag = image_attributes.last.split(':')
    {
        registry: "#{image_attributes[0]}",
        project: "#{image_attributes[1]}",
        image_name: "#{image_name}",
        tag: "#{image_tag}",
    }
  end

  # reset ingest docker image configuration to defaults on startup
  def self.revert_ingest_docker_image
    ingest_config = self.get_ingest_docker_image_config
    ingest_config.destroy if ingest_config.present?
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
          revoke_share_acl = ApplicationController.firecloud_client.create_workspace_acl(user, @config_setting)
          ApplicationController.firecloud_client.update_workspace_acl(study.firecloud_project, study.firecloud_workspace, revoke_share_acl)
        end
        # last, remove study owner access (unless project owner)
        owner = study.user.email
        Rails.logger.info "#{Time.zone.now}: revoking owner access for #{owner}"
        revoke_owner_acl = ApplicationController.firecloud_client.create_workspace_acl(owner, @config_setting)
        ApplicationController.firecloud_client.update_workspace_acl(study.firecloud_project, study.firecloud_workspace, revoke_owner_acl)
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
        restore_share_acl = ApplicationController.firecloud_client.create_workspace_acl(user, share_permission, can_share, can_compute)
        ApplicationController.firecloud_client.update_workspace_acl(study.firecloud_project, study.firecloud_workspace, restore_share_acl)
      end
      # last, restore study owner access (unless project is owned by user)
      owner = study.user.email
      Rails.logger.info "#{Time.zone.now}: restoring WRITER access for #{owner}"
      # restore permissions, setting compute acls correctly (disabled in production for COMPUTE_BLACKLIST projects)
      restore_owner_acl = ApplicationController.firecloud_client.create_workspace_acl(owner, 'WRITER', true, Rails.env == 'production' ? false : true)
      ApplicationController.firecloud_client.update_workspace_acl(study.firecloud_project, study.firecloud_workspace, restore_owner_acl)
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
    api_ok = ApplicationController.firecloud_client.api_available?

    if !api_ok
      current_status = ApplicationController.firecloud_client.api_status
      Rails.logger.error "#{Time.zone.now}: ALERT: FIRECLOUD API SERVICE INTERRUPTION -- current status: #{current_status}"
      SingleCellMailer.firecloud_api_notification(current_status).deliver_now
    end
  end

  # set/revoke readonly access on public workspaces for READ_ONLY_SERVICE_ACCOUNT
  def self.set_readonly_service_account_permissions(grant_access)
    if ApplicationController.read_only_firecloud_client.present? && ApplicationController.read_only_firecloud_client.registered?
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
    groups = ApplicationController.firecloud_client.get_user_groups
    ws_owner_group = groups.detect {|group| group['groupName'] == FireCloudClient::WS_OWNER_GROUP_NAME &&
        group['role'] == 'Admin'}
    # create group if not found
    if ws_owner_group.present?
      ws_owner_group
    else
      # create and return group
      ApplicationController.firecloud_client.create_user_group(FireCloudClient::WS_OWNER_GROUP_NAME)
      ApplicationController.firecloud_client.get_user_group(FireCloudClient::WS_OWNER_GROUP_NAME)
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
      if ApplicationController.read_only_firecloud_client.present?
        if self.value_changed?
          AdminConfiguration.set_readonly_service_account_permissions(self.convert_value_by_type)
        end
      else
        errors.add(:config_type, '- You have not enabled the read-only service account yet.  You must enable this account first before continuing.  Please see https://github.com/broadinstitute/single_cell_portal_core#running-the-container#read-only-service-account for more information.')
      end
    end
  end

  # ensure docker image is present before allowing config to be created
  # this will prevent using bad Docker image names and breaking parses
  def ensure_docker_image_present
    begin
      image = AdminConfiguration.get_ingest_docker_image_attributes(image_name: self.value)
      image_manifest_url = "https://#{image[:registry]}/v2/#{image[:project]}/#{image[:image_name]}/manifests/#{image[:tag]}"
      response = RestClient.get image_manifest_url
      # ensure this is a Docker image manifest
      manifest_matcher = /docker.*manifest/
      manifest_content_type = response.headers[:content_type]
      if manifest_content_type !~ manifest_matcher
        errors.add(:value, "does not appear to be a valid Docker image manifest: #{manifest_content_type} does not match #{manifest_matcher}")
      else
        true # pass validation
      end
    rescue RestClient::Exception => e
      errors.add(:value, "is invalid (#{e.message}) - please specify a valid image URI")
    rescue => e
      errors.add(:value, "was unable to validate due to an error: #{e.message}")
    end
  end

  def strip_whitespace
    self.value.strip! if self.value.present?
  end
end

