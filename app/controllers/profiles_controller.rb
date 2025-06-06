class ProfilesController < ApplicationController

  ##
  #
  # ProfilesController: controller to allow users to manage certain aspects of their user account
  # since user accounts map to Google profiles, we cannot alter anything about the source profile
  #
  ##

  before_action :set_user
  before_action :set_toggle_id, only: [:update, :update_study_subscription, :update_share_subscription]
  before_action do
    authenticate_user!
    check_profile_access
  end
  before_action :check_firecloud_registration, only: :update_firecloud_profile

  def show
    @study_shares = StudyShare.where(email: @user.email)
    @studies = Study.where(user_id: @user.id)
    @fire_cloud_profile = FireCloudProfile.new
    begin
      user_client = FireCloudClient.new(user: current_user, project: FireCloudClient::PORTAL_NAMESPACE)
      profile = user_client.get_profile
      profile['keyValuePairs'].each do |attribute|
        if @fire_cloud_profile.respond_to?("#{attribute['key']}=")
          @fire_cloud_profile.send("#{attribute['key']}=", attribute['value'])
        end
      end
    rescue => e
      ErrorTracker.report_exception(e, current_user, params)
      MetricsService.report_error(e, request, current_user)
      logger.info "#{Time.zone.now}: unable to retrieve FireCloud profile for #{current_user.email}: #{e.message}"
    end
  end

  def update
    if @user.update(user_params)
      @notice = 'Account update successfully recorded.'
    else
      @alert = @user.errors.full_messages.join(', ')
    end
  end

  def update_study_subscription
    @study = Study.find(params[:study_id])
    update = study_params[:default_options][:deliver_emails] == 'true'
    opts = @study.default_options
    if @study.update(default_options: opts.merge(deliver_emails: update))
      @notice = 'Study email subscription update successfully recorded.'
    else
      @alert = @share.errors.full_messages.join(', ')
    end
    render action: :update
  end

  def update_share_subscription
    @share = StudyShare.find(params[:study_share_id])
    update = study_share_params[:deliver_emails] == 'true'
    if @share.update(deliver_emails: update)
      @notice = 'Study email subscription update successfully recorded.'
    else
      @alert = @share.errors.full_messages.join(', ')
    end
    render action: :update
  end

  def update_firecloud_profile
    begin
      @fire_cloud_profile = FireCloudProfile.new(profile_params)
      if @fire_cloud_profile.valid?
        user_client = FireCloudClient.new(user: current_user, project: FireCloudClient::PORTAL_NAMESPACE)
        user_client.set_profile(profile_params)
        # log that user has registered so we can use this elsewhere
        if !current_user.registered_for_firecloud
          current_user.update(registered_for_firecloud: true)
        end
        @notice = "Your FireCloud profile has been successfully updated."
        # now check if user is part of 'all-portal' user group
        current_user.add_to_portal_user_group
      else
        logger.info "#{Time.zone.now}: error in updating FireCloud profile for #{current_user.email}: #{@fire_cloud_profile.errors.full_messages}"
        respond_to do |format|
          format.js {render :get_firecloud_profile}
        end
      end
    rescue => e
      ErrorTracker.report_exception(e, current_user, params)
      MetricsService.report_error(e, request, current_user)
      logger.info "#{Time.zone.now}: unable to update FireCloud profile for #{current_user.email}: #{e.message}"
      @alert = "An error occurred when trying to update your FireCloud profile: #{e.message}"
    end
  end

  def accept_tos
    @previous_acceptance = TosAcceptance.where(
      email: @user.email, :version.ne => TosAcceptance::CURRENT_VERSION
    ).order_by(&:version).last
  end

  def record_tos_action
    user_accepted = tos_params[:action] == 'accept'
    if user_accepted
      # record user acceptance, which tracks the email, the date, and the version of the ToS

      organization = tos_params[:organization]
      organizational_email = tos_params[:organizational_email]
      begin
        @user.update!(organization:, organizational_email:)
      rescue Mongoid::Errors::Validations => e
        message = @user.errors.errors[0].message

        # Log errors to Sentry and Mixpanel
        ErrorTracker.report_exception(e, current_user, tos_params)
        MetricsService.report_error(e, request, current_user)

        # Record error in local logs
        message_with_email = "#{message}: \\\"#{organizational_email}\\\""
        logger.info "#{Time.zone.now}: failed to record Terms of Service (TOS): #{message_with_email}"

        # Report an actionable error message to user
        workaround = 'Please give a valid email address, or leave field blank'
        redirect_to merge_default_redirect_params(accept_tos_path, scpbr: params[:scpbr]),
                    alert: "#{message_with_email}.  #{workaround}.  #{SCP_SUPPORT_EMAIL}" and return
      end
      TosAcceptance.create(email: @user.email)
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), notice: 'Terms of Service response successfully recorded.' and return
    else
      sign_out @user
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]),
                  alert: "You must accept the Terms of Service to sign in.  #{SCP_SUPPORT_EMAIL}" and return
    end
  end

  private

  # set the requested user account
  def set_user
    @user = User.find(params[:id])
  end

  def set_toggle_id
    @toggle_id = params[:toggle_id]
  end

  # make sure the current user is the same as the requested profile
  def check_profile_access
    if current_user.email != @user.email
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]),
                  alert: "You do not have permission to perform that action.  #{SCP_SUPPORT_EMAIL}" and return
    end
  end

  def check_firecloud_registration
    unless current_user.registered_for_firecloud
      terra_link = view_context.link_to('registered with Terra',
                                        'https://support.terra.bio/hc/en-us/articles/360028235911-How-to-register-for-a-Terra-account',
                                        target: :_blank)
      alert = "You may not update your Terra profile until you have #{terra_link}.  #{SCP_SUPPORT_EMAIL}"
      redirect_to view_profile_path(current_user.id), alert: alert and return
    end
  end

  def user_params
    params.require(:user).permit(:admin_email_delivery, :use_short_session, :organization, :organizational_email)
  end

  def study_share_params
    params.require(:study_share).permit(:deliver_emails)
  end

  def study_params
    params.require(:study).permit(:default_options => [:deliver_emails])
  end

  # parameters for service account profile
  def profile_params
    params.require(:fire_cloud_profile).permit(:contactEmail, :email, :firstName, :lastName, :institute, :institutionalProgram,
                                            :nonProfitStatus, :pi, :programLocationCity, :programLocationState,
                                            :programLocationCountry, :title, :termsOfService)
  end

  def tos_params
    params.require(:tos).permit(:action, :organization, :organizational_email)
  end
end
