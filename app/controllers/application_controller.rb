
class ApplicationController < ActionController::Base

  extend ErrorTracker

  ###
  #
  # These are methods that are not specific to any one controller and are inherited into all
  # They are all either access control filters or instance variable setters
  #
  ###

  before_action :set_csrf_headers

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  before_action :get_download_quota
  before_action :get_deployment_notification
  before_action :set_selected_branding_group
  before_action :check_tos_acceptance

  rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_csrf

  def self.papi_client
    @@papi_client ||= PapiClient.new
  end

  def self.big_query_client
    @@big_query_client ||= BigQueryClient.new.client
  end

  # set current_user for use outside of controllers
  # from https://stackoverflow.com/questions/2513383/access-current-user-in-model
  around_action :set_current_user
  def set_current_user
    Current.user = current_user
    if current_user.present?
      current_user.update_last_access_at!
    end
    yield
  ensure
    # to address the thread variable leak issues in Puma/Thin webserver
    Current.user = nil
  end

  # auth action for portal admins
  def authenticate_admin
    unless current_user.admin?
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: 'You do not have permission to access that page.' and return
    end
  end

  # auth action for portal reporters
  def authenticate_reporter
    unless current_user.acts_like_reporter?
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: 'You do not have permission to access that page.' and return
    end
  end

  # retrieve the current download quota
  def get_download_quota
    @download_quota = self.class.get_download_quota
  end

  #see if deployment has been scheduled
  def get_deployment_notification
    @deployment_notification = DeploymentNotification.first
  end

  # check whether the portal has been put in 'safe-mode'
  def check_access_settings
    redirect = request.referrer.nil? ? site_path : request.referrer
    access = AdminConfiguration.firecloud_access_enabled?
    if !access
      redirect_to merge_default_redirect_params(redirect, scpbr: params[:scpbr]), alert: "Study access has been temporarily disabled by the site adminsitrator.  Please contact #{view_context.mail_to('scp-support@broadinstitute.zendesk.com')} if you require assistance." and return
    end
  end

  # load default study options for updating
  def set_study_default_options
    @default_cluster = @study.default_cluster
    @default_cluster_annotations = {
        'Study Wide' => @study.viewable_metadata.map {|metadata| metadata.annotation_select_option }
    }
    unless @default_cluster.nil?
      @default_cluster_annotations['Cluster-based'] = @default_cluster.cell_annotations
                                                          .keep_if {|annot| @default_cluster.can_visualize_cell_annotation?(annot)}
                                                          .map {|annot| @default_cluster.formatted_cell_annotation(annot)}
    end
  end

  # rescue from an invalid csrf token (if user logged out in another window, or some kind of spoofing attack)
  def invalid_csrf(exception)
    ErrorTracker.report_exception(exception, current_user, {request_url: request.url, params: params.to_unsafe_hash})
    @alert = "We're sorry, but the change you wanted was rejected by the server."
    respond_to do |format|
      format.html {render template: '/layouts/422', status: 422}
      format.js {render template: '/layouts/session_expired', status: 422}
      format.json {render json: {error: @alert}, status: 422}
    end
  end

  # set branding group if present
  def set_selected_branding_group
    if params[:scpbr].present?
      @selected_branding_group = BrandingGroup.find_by(name_as_id: params[:scpbr])
    end
  end

  # make sure that users are accepting the Terms of Service
  def check_tos_acceptance
    # only redirect if user is signed in, has not accepted the ToS, and is not currently on the accept_tos page
    if user_signed_in? && !TosAcceptance.accepted?(current_user) && request.path != accept_tos_path(current_user.id)
      redirect_to accept_tos_path(current_user.id) and return
    end
  end

  # merge in extra parameters on redirects as necessary
  def merge_default_redirect_params(redirect_route, extra_params={})
    merged_redirect_url = redirect_route.dup
    extra_params.each do |key, value|
      if value.present?
        if redirect_route.include?('?')
          merged_redirect_url += "&#{key}=#{value}"
        else
          merged_redirect_url += "?#{key}=#{value}"
        end
      end
    end
    merged_redirect_url
  end

  # validate that a signed_url is valid for redirect (for security purposes)
  def is_valid_signed_url?(signed_url)
    uri = URI.parse(signed_url)
    parsed_query = Rack::Utils.parse_query(uri.query)
    # return true if the scheme is https, the hostname matches a known GCS host, and the query string parameters have the correct keys
    uri.scheme == 'https' && ValidationTools::GCS_HOSTNAMES.include?(uri.hostname) && parsed_query.keys == ValidationTools::SIGNED_URL_KEYS
  end

  def handle_401
    respond_to do |format|
      format.html {redirect_to new_user_session_path, alert: 'Your session has expired.'}
      format.js {render js: "alert('Your session has expired; Please log in again')"}
    end
  end

  protected

  # patch to supply CSRF token on all ajax requests if it is not present
  def set_csrf_headers
    if request.xhr?
      cookies['XSRF-TOKEN'] = form_authenticity_token if cookies['XSRF-TOKEN'].blank?
    end
  end

  # protected method to allow access from other controllers
  def self.get_download_quota
    config_entry = AdminConfiguration.find_by(config_type: 'Daily User Download Quota')
    if config_entry.nil? || config_entry.value_type != 'Numeric'
      # fallback in case entry cannot be found or is set to wrong type
      @download_quota = 2.terabytes
    else
      @download_quota = config_entry.convert_value_by_type
    end
  end
end
