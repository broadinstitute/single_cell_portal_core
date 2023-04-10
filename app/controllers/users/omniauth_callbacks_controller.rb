class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController

  ###
  #
  # This is the OAuth2 endpoint for receiving callbacks from Google after successful authentication
  #
  ###

  def google_oauth2
    # You need to implement the method below in your model (e.g. app/models/user.rb)
    @user = User.from_omniauth(request.env["omniauth.auth"])

    begin
      self.class.validate_scopes_from_params(params)
    rescue SecurityError => e
      logger.error e.message
      ErrorTracker.report_exception(e, @user, params)
      MetricsService.report_error(e, request, @user)
      sign_out @user if @user.present?
      head 400 and return
    end

    if @user.persisted?
      @user.generate_access_token
      # update a user's FireCloud status
      @user.delay.update_firecloud_status
      sign_in(@user)
      @alert = nil
      # check if user needs to accept updated Terra ToS
      if @user.must_accept_terra_tos?
        redirect_to exceptions_terra_tos_path and return
      end
      if TosAcceptance.accepted?(@user)
        MetricsService.merge_identities_in_mixpanel(@user, cookies)
        # validate that the Referer header has not been manipulated
        requested_path = set_omniauth_redirect(request, @user) || site_path
        redirect_to requested_path, alert: @alert
      else
        redirect_to accept_tos_path(@user.id), alert: @alert
      end
    else
      redirect_to new_user_session_path
    end
  end

  # compare the granted scopes from the OAuth callback against those configured for the provider
  # if extra scopes have been granted (through spoofing or direct editing of the request redirect before consenting)
  # then raise a SecurityError and halt execution
  def self.validate_scopes_from_params(params)
    requested_scopes = params[:scope].split
    configured_scopes = SingleCellPortal::Application::BASIC_GOOGLE_SCOPES
    requested_scopes.each do |scope|
      # trim auth URL off of name for comparison
      scope_name = scope.starts_with?('https://www.googleapis.com/auth/') ? scope.split('/').last : scope
      if !configured_scopes.include?(scope_name)
        error_message = "Invalid scope requested in OAuth callback: #{scope_name}, not in: #{configured_scopes}"
        raise SecurityError.new(error_message)
      end
    end
  end

  # validate omniauth.origin is redirecting to same host
  # will allow redirect if hostnames match, otherwise will return nil to force redirect to home page
  # malicious redirects are logged as SecurityError in Sentry/Mixpanel
  def set_omniauth_redirect(request, user)
    begin
      return nil if request.env['omniauth.origin'].nil? # no referrer set, so default logic applies

      hostname = URI.parse(request.env['omniauth.origin']).hostname
      if hostname == ENV['HOSTNAME']
        request.env['omniauth.origin']
      else
        raise SecurityError, "Invalid origin: #{hostname} requested, does not match #{ENV['HOSTNAME']}"
      end
    rescue SecurityError => e
      Rails.logger.error e.message
      # we can't use RequestUtils.log_exception as this isn't a handled request exception
      ErrorTracker.report_exception(e, user, request.params)
      MetricsService.report_error(e, request, user, nil)
      nil
    rescue URI::InvalidURIError, NoMethodError => e
      Rails.logger.error "Error processing omniauth.origin: (#{e.class.name}) #{e.message}"
      ErrorTracker.report_exception(e, user, request.params)
      MetricsService.report_error(e, request, user, nil)
      nil
    end
  end
end
