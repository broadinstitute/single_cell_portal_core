class AdminConfigurationsController < ApplicationController

  ###
  #
  # FILTERS & SETTINGS
  #
  ###

  before_action :set_admin_configuration, only: [:show, :edit, :update, :destroy]
  before_action do
    authenticate_user!
    authenticate_admin
  end

  ###
  #
  # ADMINCONFIGURATION OBJECT METHODS
  #
  ###

  # GET /admin_configurations
  # GET /admin_configurations.json
  def index
    @admin_configurations = AdminConfiguration.not_in(config_type: AdminConfiguration::FIRECLOUD_ACCESS_NAME)
    @current_firecloud_status = AdminConfiguration.current_firecloud_access

    case @current_firecloud_status
      when 'on'
        @download_status = true
        @download_status_label = "<span class='label label-success'><i class='fas fa-check'></i> Enabled</span>".html_safe
      when 'readonly'
        @download_status = true
        @download_status_label = "<span class='label label-warning'><i class='fas fa-exclamation-circle'></i> Read Only</span>".html_safe
      when 'off'
        @download_status = false
        @download_status_label = "<span class='label label-danger'><i class='fas fa-times'></i> Disabled</span>".html_safe
      when 'local-off'
        @download_status = false
        @download_status_label = "<span class='label label-danger'><i class='fas fa-times'></i> Disabled Locally</span>".html_safe
    end
    @users = User.all.to_a

    # load actions for UI
    @administrative_tasks = []
    @task_descriptions = {}
    @task_http_methods = {}
    available_admin_actions.each do |action|
      @administrative_tasks << [action[:name], action[:url]]
      @task_descriptions[action[:name]] = action[:description]
      @task_http_methods[action[:name]] = action[:method]
    end
  end


  # GET /admin_configurations/1
  # GET /admin_configurations/1.json
  def show
  end

  # GET /admin_configurations/new
  def new
    @admin_configuration = AdminConfiguration.new
  end

  # GET /admin_configurations/1/edit
  def edit
  end

  # POST /admin_configurations
  # POST /admin_configurations.json
  def create
    @admin_configuration = AdminConfiguration.new(admin_configuration_params)
    respond_to do |format|
      if @admin_configuration.save
        format.html { redirect_to admin_configurations_path, notice: "Configuration option '#{@admin_configuration.config_type}' was successfully created." }
        format.json { render :show, status: :created, location: @admin_configuration }
      else
        format.html { render :new }
        format.json { render json: @admin_configuration.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /admin_configurations/1
  # PATCH/PUT /admin_configurations/1.json
  def update
    respond_to do |format|
      if @admin_configuration.update(admin_configuration_params)
        format.html { redirect_to admin_configurations_path, notice: "Configuration option '#{@admin_configuration.config_type}' was successfully updated." }
        format.json { render :show, status: :ok, location: @admin_configuration }
      else
        format.html { render :edit }
        format.json { render json: @admin_configuration.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /admin_configurations/1
  # DELETE /admin_configurations/1.json
  def destroy
    @admin_configuration.destroy
    respond_to do |format|
      format.html { redirect_to admin_configurations_path, notice: "Configuration option '#{@admin_configuration.config_type}' was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  ###
  #
  # SITE ADMIN ACTIONS
  #
  ###

  # disable/enable all downloads by revoking workspace ACLs
  def manage_firecloud_access
    @config = AdminConfiguration.find_or_create_by(config_type: AdminConfiguration::FIRECLOUD_ACCESS_NAME, value_type: 'String')
    status = params[:firecloud_access][:status].downcase
    begin
      case status
        when 'on'
          message = "FireCloud access setting recorded successfully as 'on'."
          # if status was set to local-off, don't bother changing remote workspace acls as they are unchanged
          unless @config.value == 'local-off'
            AdminConfiguration.enable_firecloud_access
          end
          # turn notifications of API outages back on by default
          notifier_config = AdminConfiguration.find_or_create_by(config_type: AdminConfiguration::API_NOTIFIER_NAME, value_type: 'Boolean')
          if notifier_config.value != '1'
            notifier_config.update(value: '1')
            message += ' Notifications for API outages were also re-enabled.'
          end
          @config.update(value: status)
          redirect_to admin_configurations_path, alert: message
        when 'off'
          AdminConfiguration.configure_firecloud_access('off')
          @config.update(value: status)
          redirect_to admin_configurations_path, alert: "FireCloud access setting recorded successfully as 'off'.  Portal study & workspace access is now disabled."
        when 'local-off'
          @config.update(value: status)
          redirect_to admin_configurations_path, alert: "FireCloud access setting recorded successfully as 'local-off' (local acccess disabled).  Portal study & download access is now disabled, but remote FireCloud permissions are unchanged."
        when 'readonly'
          AdminConfiguration.configure_firecloud_access('readonly')
          @config.update(value: status)
          redirect_to admin_configurations_path, alert: "FireCloud access setting recorded successfully as 'readonly'.  Downloads are still enabled, but portal study access and workspace computes are disabled."
        else
          # do nothing, protect against bad status parameters
          nil
          redirect_to admin_configuration_path, alert: 'Invalid configuration option; ignored.'
      end
    rescue => e
      ErrorTracker.report_exception(e, current_user, params.to_unsafe_hash)
      logger.error "#{Time.zone.now}: error in setting download status to #{status}; #{e.message}"
      redirect_to admin_configurations_path, alert: "An error occured while turing #{status} downloads: #{e.message}" and return
    end
  end

  # reset user download quotas ahead of daily reset
  def reset_user_download_quotas
    User.update_all(daily_download_quota: 0)
  end

  # restart all orphaned jobs to allow them to continue
  def restart_locked_jobs
    jobs_restarted = AdminConfiguration.restart_locked_jobs
    if jobs_restarted > 0
      @message = "All locked jobs have successfully been restarted (#{jobs_restarted} total)."
    else
      @message = 'No orphaned jobs were found.'
    end
  end

  # force the FireCloudClient to reinitialize and get new access tokens & connects to GSC
  def refresh_api_connections
    expiration = ApplicationController.firecloud_client.expires_at
    storage_issue_date = ApplicationController.firecloud_client.storage_issued_at
    # reinitialize the firecloud client object (forces new access tokens)
    refresh_status = Study.refresh_firecloud_client
    if refresh_status == true && (expiration < ApplicationController.firecloud_client.expires_at && storage_issue_date <  ApplicationController.firecloud_client.storage_issued_at)
      logger.info "#{Time.zone.now}: Refreshing API client tokens and drivers.  New expiry: #{ApplicationController.firecloud_client.expires_at}"
      @notice = "API Client successfully refreshed.  Tokens are now valid until #{ApplicationController.firecloud_client.expires_at.strftime('%D %r')} and will renew automatically."
      @alert = ''
    else
      @notice = ''
      @alert = "Error refreshing API client: #{refresh_status}."
    end
  end

  # retrieve the firecloud registration for the portal service account
  def get_service_account_profile
    @profile_info = {}
    @client = params[:account] == 'readonly' ? ApplicationController.read_only_firecloud_client : ApplicationController.firecloud_client
    @portal_service_account = @client.issuer

    begin
      if @client.registered?
        profile = @client.get_profile
        profile['keyValuePairs'].each do |attribute|
          @profile_info[attribute['key']] = attribute['value']
        end
      end
    rescue => e
      ErrorTracker.report_exception(e, current_user, params.to_unsafe_hash)
      logger.error "#{Time.zone.now}: unable to retrieve service account FireCloud registration: #{e.message}"
    end
  end

  # register or update the FireCloud profile of the portal service account
  def update_service_account_profile
    @client = params[:account] == 'readonly' ? ApplicationController.read_only_firecloud_client : ApplicationController.firecloud_client

    begin
      @client.set_profile(profile_params)
      @notice = "The portal service account FireCloud profile has been successfully updated."
    rescue => e
      ErrorTracker.report_exception(e, current_user, params.to_unsafe_hash)
      logger.error "#{Time.zone.now}: unable to update service account FireCloud registration: #{e.message}"
      @alert = "Unable to update portal service account FireCloud profile: #{e.message}"
    end
  end

  # get the current status of FireCloud API services
  def firecloud_api_status
    begin
      @status = ApplicationController.firecloud_client.api_status
    rescue => e
      ErrorTracker.report_exception(e, current_user, params.to_unsafe_hash)
      logger.error "#{Time.zone.now}: unable to retrieve FireCloud API status due to: #{e.message}"
      @status = {error: "An error occurred while fetching the FireCloud API status: #{e.message}"}
    end
  end

  # make sure all portal users are a member of the portal-wide user group (if enabled)
  def sync_portal_user_group
    user_group_config = AdminConfiguration.find_by(config_type: 'Portal FireCloud User Group')
    if user_group_config.present?
      begin
        @group_name = user_group_config.value
        @new_users = []
        # first check to see if group has already been created in FireCloud
        groups = ApplicationController.firecloud_client.get_user_groups
        matching_group = groups.find {|g| g['groupName'] == @group_name}
        if matching_group.nil?
          # we need to create the group before continuing
          user_group = ApplicationController.firecloud_client.create_user_group(@group_name)
        else
          user_group = ApplicationController.firecloud_client.get_user_group(@group_name)
        end
        # now collect all registered portal users and add to the list
        portal_users = User.where(provider: 'google_oauth2').to_a
        portal_users.each do |user|
          unless user_group['membersEmails'].include?(user.email)
            # check if user is FireCloud member first
            user_client = FireCloudClient.new(user, FireCloudClient::PORTAL_NAMESPACE)
            if user_client.registered?
              logger.info "#{Time.zone.now}: adding #{user.email} to #{@group_name}"
              ApplicationController.firecloud_client.add_user_to_group(@group_name, 'member', user_email)
              @new_users << user.email
            else
              logger.info "#{Time.zone.now}: skipping #{user.email}; not registered in FireCloud yet."
            end
          end
        end
        logger.info "#{Time.zone.now}: User group #{@group_name} successfully synchronized"
      rescue => e
        ErrorTracker.report_exception(e, current_user, params.to_unsafe_hash)
        logger.error "#{Time.zone.now}: Error in synchronizing portal user group #{@group_name}: #{e.message}"
        @alert = "Unable to synchronize user group #{@group_name} due to an error: #{e.message}"
      end
    else
      @alert = "You have not specified a portal-wide user group yet.  Please create a 'Portal FireCloud User Group' configuration first."
    end
  end

  def select_readonly_access
    @config = AdminConfiguration.find_or_create_by(config_type: 'Read-Only Access Control', value_type: 'Boolean')
  end

  def manage_readonly_access
    @config = AdminConfiguration.find_or_create_by(config_type: 'Read-Only Access Control', value_type: 'Boolean')
    revoke_access = readonly_settings_params[:access_level] == '0'
    if @config.update(value: readonly_settings_params[:access_level])
      begin
        @success, @alert = AdminConfiguration.set_readonly_service_account_permissions(revoke_access)
      rescue => e
        ErrorTracker.report_exception(e, current_user, params.to_unsafe_hash)
        @alert = "An error occurred while trying to set the access for the readonly service account: #{e.message}"
      end
    else
      @alert = "We were unable to process your request: #{@config.errors.full_messages.join(', ')}"
    end
  end

  ###
  #
  # USER ROLES METHODS
  #
  ###

  # edit a user account (to grant permissions)
  def edit_user
    @user = User.find(params[:id])
  end

  # update a user account
  def update_user
    @user = User.find(params[:id])
    respond_to do |format|
      if @user.update(user_params)
        self.class.process_feature_flag_form_data(@user, params)
        format.html { redirect_to admin_configurations_path, notice: "User: '#{@user.email}' was successfully updated." }
      else
        format.html { render :edit_user }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # Update the user with the form data on their feature flags
  # because of the true/false/default structure, we have to have custom logic to handle the values
  def self.process_feature_flag_form_data(user, params)
    updated_flag_data = {}
    FeatureFlag.all.each do |default_flag|
      # for each possible feature flag, check if the vaule was set on the form via a field name feature_flag_<<flag name>>
      flag_form_val = params[('feature_flag_' + default_flag.name).to_sym]
      # if it was set, and not set to '-' (default), include it in the updated values
      if flag_form_val && flag_form_val != '-'
        updated_flag_data[default_flag.name] = flag_form_val == '1' ? true : false
      end
    end
    user.update!(feature_flags: updated_flag_data)
  end

  ###
  #
  # USER EMAIL METHODS
  #
  ###

  # compose an email to send all portal users
  def compose_users_email

  end

  # deliver an email to all portal users
  def deliver_users_email
    begin
      # send in background so operation doesn't time out with lots of users
      SingleCellMailer.delay.batch_users_email(users_email_params, current_user)
      @notice = 'Your email has successfully been queued for delivery and should arrive shortly.'
    rescue => e
      ErrorTracker.report_exception(e, current_user, users_email_params.to_unsafe_hash)
      logger.error "#{Time.zone.now}: Error delivering users email: #{e.message}"
      @alert = "Unabled to deliver users email due to the following error: #{e.message}"
    end
  end

  ###
  #
  # DEPLOYMENT METHODS
  #
  ###

  def view_deployment
    @deployment_notification = DeploymentNotification.first || DeploymentNotification.new
  end

  def create_deployment_notification
    @deployment_notification = DeploymentNotification.new(deployment_notification_params)
    respond_to do |format|
      if @deployment_notification.save
        @notice = "Notification banner has been scheduled."
        format.js { render :view_deployment}

      else
        format.js { render :view_deployment}
        format.json {render :json => @deployment_notification.errors, status: :unprocessable_entity}
      end
    end
  end

  def delete_deployment_notification
    @deployment_notification.destroy
    respond_to do |format|
      format.html { redirect_to admin_configurations_path, notice: "Notification banner was successfully destroyed and is no longer scheduled" }
    end
  end

  private

  ###
  #
  # SETTERS
  #
  ###

  def set_admin_configuration
    @admin_configuration = AdminConfiguration.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def admin_configuration_params
    params.require(:admin_configuration).permit(:config_type, :value_type, :value, :multiplier, configuration_options_attributes: [:id, :name, :value, :_destroy])
  end

  def user_params
    params.require(:user).permit(:id, :admin, :reporter)
  end

  # parameters for service account profile
  def profile_params
    params.require(:service_account).permit(:contactEmail, :email, :firstName, :lastName, :institute, :institutionalProgram,
                                            :nonProfitStatus, :pi, :programLocationCity, :programLocationState,
                                            :programLocationCountry, :title)
  end

  # parameters for sending user emails
  def users_email_params
    params.require(:email).permit(:subject, :from, :contents, :preview)
  end

  def readonly_settings_params
    params.require(:readonly_settings).permit(:access_level)
  end

  # parameters for deployment notifications
  def deployment_notification_params
    params.require(:deployment_notification).permit(:deployment_time, :message)
  end

  # list of available actions to perform
  def available_admin_actions
    [
        {
            name: 'Reset User Download Quotas',
            description: 'Rest all user daily download quota back to 0.',
            url: reset_user_download_quotas_path,
            method: 'POST'
        },
        {
            name: 'Unlock Orphaned Jobs',
            description: 'Restart any parse jobs that may have been orphaned due to a restart or unexpected crash.',
            url: restart_locked_jobs_path,
            method: 'POST'
        },
        {
            name: 'Refresh API Clients',
            description: 'Force the FireCloud API client to regenerate all access tokens (may be needed after service outage).',
            url: refresh_api_connections_path,
            method: 'POST'
        },
        {
            name: 'Manage Main Service Account FireCloud Registration',
            description: 'Create or update the FireCloud registration of the main portal service account.',
            url: get_service_account_profile_path(account: 'main'),
            method: 'GET'
        },
        {
            name: 'Manage Read-Only Service Account FireCloud Registration',
            description: 'Create or update the FireCloud registration of the read-only portal service account.',
            url: get_service_account_profile_path(account: 'readonly'),
            method: 'GET'
        },
        {
            name: 'FireCloud API Status',
            description: 'Get the current status of all FireCloud services',
            url: firecloud_api_status_path,
            method: 'GET'
        },
        {
            name: 'Synchronize FireCloud User Group',
            description: 'Ensure that all registered portal members are a member of the portal-wide user group list (can be used for FireCloud read permissions to certain public workspaces for reference data, if needed).',
            url: sync_portal_user_group_path,
            method: 'GET'
        }
    ]
  end
end
