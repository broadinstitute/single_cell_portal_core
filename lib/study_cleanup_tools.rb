# study_cleanup_tools.rb
#
# module for ensuring that each test build starts with clean schemas and Terra billing projects
# methods are safeguarded so that they cannot be run on deployed instances
# methods can be run against a local instance by passing allow_dev_env: true (but not recommended)

module StudyCleanupTools

  # disallow running an cleanup commands on deployed production & staging hosts
  DISALLOWED_HOSTS = /singlecell(-staging)?\.broadinstitute/

  # disallow running deletes against any of these projects
  DISALLOWED_BILLING_PROJECTS = %w(single-cell-portal single-cell-portal-staging)

  # delete all studies and remove associated Terra workspaces & Google buckets
  # can only be invoked in the test or pentest environment
  #
  # * *params*
  #   - +allow_dev_env+: (Boolean) => allow execution of this method in development environment (default: false)
  #
  # * *raises*
  #   - (RuntimeError) => if command cannot be run for failing a security check (hostname, project, environment, etc)
  #
  # * *returns*
  #   - (Integer) => count of studies that were deleted
  def self.destroy_all_studies_and_workspaces(allow_dev_env: false)
    raise_exception_unless_true('permit_environment?') { permit_environment?(allow_dev_env) }
    raise_exception_unless_true('permit_hostname?') { permit_hostname? }
    raise_exception_unless_true('confirm_delete_request?') { confirm_delete_request? } if !!(allow_dev_env && Rails.env.development?)
    study_count = 0
    Study.all.each do |study|
      # do not mass delete studies in protected projects
      if permit_billing_project?(study.firecloud_project)
        study.destroy_and_remove_workspace
        study_count += 1
      end
    end
    study_count
  end

  # delete all Terra workspaces in a project that do not have a study associated with them in the given env/schema
  # will ignore any workspaces created by different service accounts/users
  # by default will only run against test/pentest environment during continuous integration build
  #
  # * *params*
  #   - +project_name+: (String) => Name of Terra billing project (defaults to FireCloudClient::PORTAL_NAMESPACE )
  #   - +allow_dev_env+: (Boolean) => allow execution of this method in development environment (default: false)
  #
  # * *raises*
  #   - (RuntimeError) => if command cannot be run for failing a security check (hostname, project, environment, etc)
  #
  # * *returns*
  #   - (Integer) => count of workspaces that were deleted
  def self.delete_all_orphaned_workspaces(project_name = FireCloudClient::PORTAL_NAMESPACE, allow_dev_env: false)
    raise_exception_unless_true('permit_environment?') { permit_environment?(allow_dev_env) }
    raise_exception_unless_true('permit_hostname?') { permit_hostname? }
    raise_exception_unless_true('permit_billing_project?') { permit_billing_project?(project_name) }
    raise_exception_unless_true('is_continuous_integration?') { is_continuous_integration? }
    raise_exception_unless_true('confirm_delete_request?') { confirm_delete_request? } if !!(allow_dev_env && Rails.env.development?)
    workspaces = ApplicationController.firecloud_client.workspaces(project_name)
    workspace_count = 0

    # these were corrupted during a partial Terra outage, and for now, cleaning them out is more difficult
    # than just leaving them be.  Otherwise the deletion attempt hangs for several minutes
    corrupted_workspace_names = %w[upload-wizard-test-pb6y0 main-validation-study-hnds4 main-validation-study-szzob
      testing-study-jdwjl testing-study-6ec03b371c7cf59262df98424ff516e1 new-study-99f2a94b-f8a6-4efb-aa3b-4ecef24e1dad
      test-study-06387e09-6661-45b5-bc1b-4fc507bd19ea download-agreement-686b0d44c83659cd70616a3f0874fde5]
    workspaces.each do |workspace|
      ws_attr = workspace.dig('workspace')
      ws_name = ws_attr['name']
      ws_project = ws_attr['namespace']
      ws_owner = ws_attr['createdBy']
      existing_study = Study.where(firecloud_project: ws_project).any_of(
        { firecloud_workspace: ws_name }, { internal_workspace: ws_name }
      )
      if existing_study.present?
        puts "skipping #{ws_project}/#{ws_name} as it belongs to #{existing_study.accession}"
        next
      elsif corrupted_workspace_names.include?(ws_name)
        puts "skipping #{ws_project}/#{ws_name} as it is corrupted"
      else
        begin
          if service_account_created_workspace?(workspace)
            print "deleting #{ws_project}/#{ws_name}... "
            ApplicationController.firecloud_client.delete_workspace(ws_project, ws_name)
            workspace_count += 1
            puts "#{ws_project}/#{ws_name} successfully deleted"
          else
            puts "skipping #{ws_project}/#{ws_name} because it was created by #{ws_owner}"
          end
        rescue => e
          puts "Unable to delete #{ws_project}/#{ws_name} due to: #{e.class.name} - #{e.message}"
        end
      end
    end
    workspace_count
  end

  ##
  # security safeguards to prevent accidental deletes of production/staging workspaces and studies
  ##

  # handler to run a security check and raise an error on returning false to halt execution
  #
  # * *params*
  #   - +validation_name+: (String) => name of validation being run (for error message)
  #   - +&block+: (Proc) => validation method to execute that returns true/false
  #
  # * *raises*
  #   - (RuntimeError) => raise exception if security check returns false to halt parent method execution
  def self.raise_exception_unless_true(validation_name, &block)
    valid_command = yield
    if !valid_command
      # report validation that failed and method caller
      raise RuntimeError.new("#{validation_name} failed validation when calling #{self.name}##{caller_locations.first.label}")
    end
  end

  # ensure commands cannot be run on deployed hosts
  #
  # * *returns*
  #   - (Boolean) => true/false if hostname is permitted
  def self.permit_hostname?
    Socket.gethostname !~ DISALLOWED_HOSTS
  end

  # ensure commands cannot be run in production/staging environments
  # can be run manually in development if allow_dev_env is set to true
  #
  # * *params*
  #   - +allow_dev_env+: (Boolean) => true/false to allow running command in development environment (defaults to false)
  #
  # * *returns*
  #   - (Boolean) => true/false if environment is permitted
  def self.permit_environment?(allow_dev_env = false)
    if allow_dev_env
      Rails.env.test? || Rails.env.pentest? || Rails.env.development?
    else
      Rails.env.test? || Rails.env.pentest?
    end
  end

  # ensure commands cannot be run in production/staging environments
  # can be run manually in development if allow_dev_env is set to true
  #
  # * *returns*
  #   - (Boolean) => true/false if this is a CI run
  def self.is_continuous_integration?
    # must do strict equality comparison, otherwise any value for ENV['CI'] will evaluate to true
    # also boolean ENV variables are set as strings in Ruby
    ENV['CI'].to_s === 'true'
  end

  # ensure requested billing project is not disallowed, and is the configured project for this instance
  #
  # * *params*
  #   - +project_name+: (String) => name of Terra billing project
  #
  # * *returns*
  #   - (Boolean) => true/false if requested projected is permitted
  def self.permit_billing_project?(project_name)
    !!(!DISALLOWED_BILLING_PROJECTS.include?(project_name) && project_name == FireCloudClient::PORTAL_NAMESPACE)
  end

  # is requested workspace created by portal service account
  #
  # * *returns*
  #   - (Boolean) => true/false if workspace was created by configured service account
  def self.service_account_created_workspace?(workspace_attributes)
    ApplicationController.firecloud_client.issuer == workspace_attributes.with_indifferent_access.dig(:workspace, :createdBy)
  end

  # ask for extra confirmation in development environment, will require user to enter text in prompt
  #
  # * *returns*
  #   - (Boolean) => true/false if user confirms with correct prompt
  def self.confirm_delete_request?
    print "Are you sure you want to run #{caller_locations.first.label}?  Please type 'Delete All' to execute: "
    STDIN.gets.strip == 'Delete All'
  end
end
