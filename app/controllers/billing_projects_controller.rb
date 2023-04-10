class BillingProjectsController < ApplicationController

  ###
  #
  # BillingProjectsController.rb - controller to manage FireCloud billing projects and their assigned users
  #
  # Since access is controller by the user's Google account, no access restrictions need to be checked as only
  # the projects and accounts the user has permissions for will be returned.
  #
  ###

  ##
  #
  # FILTERS & SETTINGS
  #
  ##

  respond_to :html, :js, :json
  before_action :authenticate_user!
  before_action :check_firecloud_registration, except: :access_request
  before_action :check_firecloud_status, except: :access_request
  before_action :create_firecloud_client, except: :access_request
  before_action :check_project_permissions, except: [:index, :create, :access_request]
  before_action :load_service_account, except: [:new_user, :create_user, :delete_user, :storage_estimate, :access_request]

  ##
  #
  # FIRECLOUD BILLING PROJECT MANAGEMENT METHODS
  #
  ##

  # get available billing accounts & projects
  def index
    @projects = {}
    billing_projects = @fire_cloud_client.get_billing_projects

    # load user list for each project
    billing_projects.each do |project|
      project_name = project['projectName']
      @projects[project_name] = {
          status: project['creationStatus'],
          role: project['role'],
          members: project['role'] == 'Owner' ? @fire_cloud_client.get_billing_project_members(project_name) : nil
      }
    end
  end

  # show new user form
  def new_user; end

  # create a new user inside a billing project
  def create_user
    role = billing_project_user_params[:role]
    email = billing_project_user_params[:email]
    begin
      @fire_cloud_client.add_user_to_billing_project(params[:project_name], role, email)
      redirect_to merge_default_redirect_params(billing_projects_path, scpbr: params[:scpbr]), notice: "#{email} has successfully been added to #{params[:project_name]} as #{role}" and return
    rescue => e
      ErrorTracker.report_exception(e, current_user, params)
      logger.error "Unable to add #{email} to #{params[:project_name]} due to error: #{e.message}"
      redirect_to merge_default_redirect_params(new_billing_project_user_path, scpbr: params[:scpbr]),
                  alert: "We were unable to add #{email} to #{params[:project_name]} due to the following error: #{e.message}.  #{SCP_SUPPORT_EMAIL}" and return
    end
  end

  # remove a user from a billing project
  def delete_user
    role = params[:role]
    email = params[:email]
    begin
      @fire_cloud_client.delete_user_from_billing_project(params[:project_name], role, email)
      redirect_to merge_default_redirect_params(billing_projects_path, scpbr: params[:scpbr]), notice: "#{email} has successfully been removed from #{params[:project_name]} as #{role}" and return
    rescue => e
      ErrorTracker.report_exception(e, current_user, params)
      logger.error "Unable to remove #{email} from #{params[:project_name]} due to error: #{e.message}"
      redirect_to merge_default_redirect_params(billing_projects_path, scpbr: params[:scpbr]),
                  alert: "We were unable to remove #{email} from #{params[:project_name]} due to the following error: " \
                         "#{e.message}'.  #{SCP_SUPPORT_EMAIL}" and return
    end
  end

  # get a list of all workspaces in a project
  def workspaces
    @workspaces = @fire_cloud_client.workspaces(params[:project_name])
    @computes = {}
    @submissions = {}
    Parallel.map(@workspaces, in_threads: 100) do |workspace|
      begin
        workspace_name = workspace['workspace']['name']
        @computes[workspace_name] = []
        @submissions[workspace_name] = nil
        submission_count = @fire_cloud_client.get_workspace_submissions(params[:project_name], workspace_name).size
        @submissions[workspace_name] = submission_count
        acl = @fire_cloud_client.get_workspace_acl(params[:project_name], workspace_name)
        acl['acl'].each do |user, permission|
          @computes[workspace_name] << {"#{user}" => {can_compute: permission['canCompute'], access_level: permission['accessLevel']} }
        end
      rescue => e
        ErrorTracker.report_exception(e, current_user, params, { workspace: workspace})
        logger.error "Error loading workspaces from #{params[:project_name]} due to error: #{e.message}"
      end
    end
  end

  # get a workspace's compute permissions
  def edit_workspace_computes
    workspace_acl = @fire_cloud_client.get_workspace_acl(params[:project_name], params[:study_name])
    @acl = {}
    workspace_acl['acl'].each do |user, permissions|
      access_level = permissions['accessLevel']
      if access_level.include?('OWNER')
        next
      else
        @acl[user] = {
            can_compute: permissions['canCompute'],
            can_share: permissions['canShare'],
            access_level: access_level
        }
      end
    end
  end

  # update a workspace's compute permissions for a given user
  def update_workspace_computes
    # construct form ID from user email
    @email = compute_params[:email]
    @form_id = @email.gsub(/[@\.]/, '-')

    begin
      # create new acl, and cast share & compute values to Booleans
      new_acl = @fire_cloud_client.create_workspace_acl(compute_params[:email],
                                                            compute_params[:access_level],
                                                            compute_params[:can_share] == 'true',
                                                            compute_params[:can_compute] == 'true')
      @fire_cloud_client.update_workspace_acl(params[:project_name], params[:study_name], new_acl)
    rescue => e
      ErrorTracker.report_exception(e, current_user, params)
      logger.error "error in updating acl for #{params[:project_name]}:#{params[:study_name]}: #{e.message}"
      @error = e.message
    end
  end

  # get a complete rollup of all storage costs for an entire project
  def storage_estimate
    workspaces = @fire_cloud_client.workspaces(params[:project_name])
    @workspaces = {}
    @total_cost = 0.0
    # parallelize retrieving workspace storage estimates
    Parallel.map(workspaces, in_threads: 100) do |workspace|
      begin
        client = FireCloudClient.new(current_user, params[:project_name])
        workspace_name = workspace.dig('workspace', 'name')
        cost_estimate = client.get_workspace_storage_cost(params[:project_name], workspace_name)
        actual_cost = cost_estimate['estimate'].gsub(/\$/, '').to_f
        @workspaces[workspace_name] = actual_cost
        @total_cost += actual_cost
      rescue => e
        ErrorTracker.report_exception(e, current_user, params)
        logger.error "Error in computing storage costs for #{params[:project_name]}: #{e.message}"
      end
    end
  end

  private

  ##
  #
  # SETTERS
  #
  ##

  def billing_project_params
    params.require(:billing_project).permit(:project_name, :billing_account)
  end

  def billing_project_user_params
    params.require(:billing_project_user).permit(:email, :role)
  end

  def compute_params
    params.require(:compute).permit(:email, :access_level, :can_compute, :can_share)
  end

  # create client scoped to current user
  def create_firecloud_client
    project_name = params[:project_name].present? ? params[:project_name] : 'single-cell-portal'
    @fire_cloud_client = FireCloudClient.new(current_user, project_name)
  end

  # load portal service account email for use in view (we don't want to display this in the portal)
  def load_service_account
    @portal_service_account = ApplicationController.firecloud_client.storage_issuer
  end

  ##
  #
  # AUTH/PERMISSON CHECKS
  #
  ##

  # make sure a user is registered for firecloud before showing billing information
  def check_firecloud_registration
    unless current_user.registered_for_firecloud
      alert = "You must complete your FireCloud registration before viewing your available billing projects.  #{SCP_SUPPORT_EMAIL}"
      redirect_to view_profile_path(current_user.id) + '#profile-firecloud', alert: alert and return
    end
  end

  # check to make sure that the current user has access to the current project
  def check_project_permissions
    projects = @fire_cloud_client.get_billing_projects
    unless projects.map {|project| project['projectName']}.include?(params[:project_name])
      redirect_to merge_default_redirect_params(billing_projects_path, scpbr: params[:scpbr]),
                  alert: "You do not have permission to perform that action.  #{SCP_SUPPORT_EMAIL}" and return
    end
  end

  # check on FireCloud API status and respond accordingly
  def check_firecloud_status
    unless ApplicationController.firecloud_client.services_available?(FireCloudClient::THURLOE_SERVICE)
      alert = "Billing projects are temporarily unavailable, so we cannot complete your request.  Please try again later.  #{SCP_SUPPORT_EMAIL}"
      respond_to do |format|
        format.js {render js: "$('.modal').modal('hide'); alert('#{alert}')" and return}
        format.html {redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]),
                                 alert: alert and return}
        format.json {head 503}
      end
    end
  end
end

