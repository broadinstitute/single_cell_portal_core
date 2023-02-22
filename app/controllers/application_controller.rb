class ApplicationController < ActionController::Base
  include RealIpLogger

  # Error modal contact message
  SCP_SUPPORT_EMAIL = "If this error persists, please contact support at:<br /><br />" \
                      "<a href='mailto:scp-support@broadinstitute.zendesk.com' data-analytics-name='scp-support-email' " \
                      "class='no-wrap'>scp-support@broadinstitute.zendesk.com</a>"

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

  before_action :check_terra_tos_acceptance, except: [:accept_tos, :record_tos_action]
  before_action :get_download_quota
  before_action :get_deployment_notification
  before_action :set_selected_branding_group
  before_action :check_tos_acceptance
  before_action :set_ab_test_assignments

  rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_csrf

  def self.papi_client
    @@papi_client ||= PapiClient.new
  end

  def self.big_query_client
    @@big_query_client ||= BigQueryClient.new.client
  end

  # getter for FireCloudClient instance
  def self.firecloud_client
    @@firecloud_client ||= FireCloudClient.new
  end

  def self.read_only_firecloud_client
    if ENV['READ_ONLY_SERVICE_ACCOUNT_KEY'].present?
      @@read_only_client ||= FireCloudClient.new(nil, FireCloudClient::PORTAL_NAMESPACE, File.absolute_path(ENV['READ_ONLY_SERVICE_ACCOUNT_KEY']))
    end
  end

  def self.data_repo_client
    @@data_repo_client ||= DataRepoClient.new
  end

  def self.hca_azul_client
    @@hca_azul_client ||= HcaAzulClient.new
  end

  # method to renew firecloud client (forces new access token for API and reinitializes storage driver)
  def self.refresh_firecloud_client
    begin
      @@firecloud_client = FireCloudClient.new
      true
    rescue => e
      ErrorTracker.report_exception(e, nil, self.firecloud_client.attributes)
      Rails.logger.error "#{Time.zone.now}: unable to refresh FireCloud client: #{e.message}"
      e.message
    end
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

  # govern how errors are rendered, depending on environment
  # development will show standard 'friendly' error pages, all other environments will use custom exceptions_app
  # from https://github.com/rails/rails/blob/main/actionpack/lib/action_controller/metal/rescue.rb#L16
  def show_detailed_exceptions?
    Rails.env.development? || Rails.env.test?
  end

  # auth action for portal admins
  def authenticate_admin
    unless current_user.admin?
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: "You do not have permission to access that page.  #{SCP_SUPPORT_EMAIL}" and return
    end
  end

  # auth action for portal reporters
  def authenticate_reporter
    unless current_user.acts_like_reporter?
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: "You do not have permission to access that page.  #{SCP_SUPPORT_EMAIL}" and return
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
      redirect_to merge_default_redirect_params(redirect, scpbr: params[:scpbr]), alert: "Study access has been temporarily disabled by the site adminsitrator.  #{SCP_SUPPORT_EMAIL}" and return
    end
  end

  # load default study options for updating
  def set_study_default_options
    @default_cluster = @study.default_cluster
    @default_cluster_annotations = {
      'Study Wide' => [],
      'Cluster-based' => [],
      'Cannot Display'=> []
    }
    metadata_annotations = AnnotationVizService.available_metadata_annotations(@study)
    metadata_annotations.each do |annot|
      annot_key = annot[:scope] == 'invalid' ? 'Cannot Display' : 'Study Wide'
      @default_cluster_annotations[annot_key] << [annot[:name], "#{annot[:name]}--#{annot[:type]}--#{annot[:scope]}"]
    end

    @default_cluster&.cell_annotations&.each do |cell_annotation|
      if @default_cluster&.can_visualize_cell_annotation?(cell_annotation)
        @default_cluster_annotations['Cluster-based'] << @default_cluster&.formatted_cell_annotation(cell_annotation)
      else
        @default_cluster_annotations['Cannot Display'] << @default_cluster&.formatted_cell_annotation(cell_annotation)
      end
    end
    # set array of viz override values, always showing current selections first
    invalid_annotation_names = @default_cluster_annotations['Cannot Display'].map(&:first).sort
    @viz_override_annotations = @study.override_viz_limit_annotations + invalid_annotation_names
    # initialize reviewer access object
    @reviewer_access = @study.reviewer_access.present? ? @study.reviewer_access : @study.build_reviewer_access
  end

  # rescue from an invalid csrf token (if user logged out in another window, or some kind of spoofing attack)
  def invalid_csrf(exception)
    ErrorTracker.report_exception(exception, current_user, params, { request_url: request.url})
    MetricsService.report_error(exception, request, current_user, @study)
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

  # Temporary sub-optimal fix for signed-in users not having accepted Terra Terms of Service
  # Context: https://broadworkbench.atlassian.net/browse/SCP-4929
  # TODO (SCP-4971): intercept API calls that need end-user credentials, and handle this at that level
  def check_terra_tos_acceptance
    if user_signed_in? &&
       current_user.must_accept_terra_tos? &&
       ![exceptions_terra_tos_path, destroy_user_session_path].include?(request.path)
      redirect_to exceptions_terra_tos_path and return
    end
  end

  # make sure that users are accepting the Terms of Service
  def check_tos_acceptance
    # only redirect if user is signed in, has not accepted the ToS, and is not currently on the accept_tos page
    if user_signed_in? &&
       !TosAcceptance.accepted?(current_user) &&
       ![accept_tos_path(current_user.id), destroy_user_session_path].include?(request.path)
      redirect_to accept_tos_path(current_user.id) and return
    end
  end

  # load any enabled A/B test sessions for the current_user
  def set_ab_test_assignments
    @ab_test_assignments = AbTest.load_assignments(request.cookies['user_id'])
  end

  # merge in extra parameters on redirects as necessary
  def merge_default_redirect_params(redirect_route, extra_params={})
    # handle case where request.referrer is nil
    merged_redirect_url = redirect_route.present? ? redirect_route.dup : site_path.dup
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

  # helper method to check all conditions before allowing a user to download file
  # verifies user permissions, study availability, and download agreements, as well as external services
  def verify_file_download_permissions(study)
    # default alert messages for redirect
    redirect_messages = {
        invalid_permission: "You either do not have permission to perform that action, or #{study.accession} does not exist.",
        not_authenticated: "You must be signed in to download data from #{study.accession}.",
        detached: "We were unable to complete your request as #{study.accession} is detached from the workspace (maybe the workspace was deleted?)",
        embargoed: "You may not download any data from #{study.accession} until #{study.embargo.try(:to_s, :long)}."
    }
    # store redirect_url and message for later
    redirect_parameters = {}

    if study.nil?
      redirect_parameters[:url] = site_path
      redirect_parameters[:message_key] = :invalid_permission
    elsif !user_signed_in?
      redirect_parameters[:url] = site_path
      redirect_parameters[:message_key] = :not_authenticated
    elsif !study.public? && !study.can_view?(current_user)
      redirect_parameters[:url] = site_path
      redirect_parameters[:message_key] = :invalid_permission
    elsif study.detached?
      redirect_parameters[:url] = site_path
      redirect_parameters[:message_key] = :detached
    elsif study.embargoed?(current_user)
      redirect_parameters[:url] = view_study_path(accession: study.accession, study_name: study.url_safe_name)
      redirect_parameters[:message_key] = :embargoed
    elsif !study.can_download?(current_user)
      redirect_parameters[:url] = view_study_path(accession: study.accession, study_name: study.url_safe_name)
      redirect_parameters[:message_key] = :invalid_permission
    elsif study.has_download_agreement? && !study.download_agreement.user_accepted?(current_user)
      head 403 and return
    end

    if redirect_parameters.any?
      redirect_to merge_default_redirect_params(redirect_parameters[:url], scpbr: params[:scpbr]),
                  alert: redirect_messages.dig(redirect_parameters[:message_key]) + "  #{SCP_SUPPORT_EMAIL}" and return
    end

    # next check if downloads have been disabled by administrator, this will abort the download
    # download links shouldn't be rendered in any case, this just catches someone doing a straight GET on a file
    # also check if workspace google buckets are available
    if !AdminConfiguration.firecloud_access_enabled? || !ApplicationController.firecloud_client.services_available?(FireCloudClient::BUCKETS_SERVICE)
      head 503 and return
    end
  end

  # generate a signed URL for a file and redirect to object in GCS
  # will account for @download_quota and redirect as necessary
  def execute_file_download(study)
    begin
      # get filesize and make sure the user is under their quota
      requested_file = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, study.bucket_id, params[:filename])
      if params[:filename].blank?
        redirect_to merge_default_redirect_params(view_study_path(accession: study.accession, study_name: study.url_safe_name), scpbr: params[:scpbr]),
                      alert: "We are unable to process your download in #{study.accession} because there is no file name provided.  #{SCP_SUPPORT_EMAIL}" and return
      end
      if requested_file.present?
        filesize = requested_file.size
        user_quota = current_user.daily_download_quota + filesize
        # check against download quota that is loaded in ApplicationController.get_download_quota
        if user_quota <= @download_quota
          @signed_url = ApplicationController.firecloud_client.execute_gcloud_method(:generate_signed_url, 0, study.bucket_id, params[:filename], expires: 15)
          current_user.update(daily_download_quota: user_quota)
        else
          redirect_to merge_default_redirect_params(view_study_path(accession: study.accession, study_name: study.url_safe_name), scpbr: params[:scpbr]),
                      alert: "You have exceeded your current daily download quota.  You must wait until tomorrow to download this file.  #{SCP_SUPPORT_EMAIL}" and return
        end
        # redirect directly to file to trigger download
        # validate that the signed_url is in fact the correct URL - it must be a GCS lin
        if is_valid_signed_url?(@signed_url)
          redirect_to @signed_url
        else
          redirect_to merge_default_redirect_params(view_study_path(accession: study.accession, study_name: study.url_safe_name), scpbr: params[:scpbr]),
                      alert: "We are unable to process your download for #{study.accession}:#{params[:filename]}.  Please try again later.  #{SCP_SUPPORT_EMAIL}" and return
        end
      else
        # send notification to the study owner that file is missing (if notifications turned on)
        SingleCellMailer.user_download_fail_notification(study, params[:filename]).deliver_now
        redirect_to merge_default_redirect_params(view_study_path(accession: study.accession, study_name: study.url_safe_name), scpbr: params[:scpbr]),
                    alert: "#{study.accession}:#{params[:filename]} could not be found.  Please contact the study owner if you require access to this file.  #{SCP_SUPPORT_EMAIL}" and return
      end
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "#{Time.zone.now}: error generating signed url for #{params[:filename]}; #{e.message}."
      redirect_to merge_default_redirect_params(request.referrer, scpbr: params[:scpbr]),
                  alert: "We were unable to download the file #{study.accession}:#{params[:filename]} do to an error: " \
                         "#{view_context.simple_format(e.message)}.  #{SCP_SUPPORT_EMAIL}" and return
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
