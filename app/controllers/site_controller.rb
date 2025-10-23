class SiteController < ApplicationController
  ###
  #
  # This is the main public controller for the portal.  All ERB template-based
  # data viewing/rendering is handled here, including submitting workflows.
  #
  ###

  ###
  #
  # FILTERS & SETTINGS
  #
  ###

  respond_to :html, :js, :json

  before_action :set_study, except: [:index, :search, :legacy_study, :get_viewable_studies, :privacy_policy, :terms_of_service,
                                     :log_action, :get_taxon, :get_taxon_assemblies, :covid19,
                                     :reviewer_access, :validate_reviewer_access]
  before_action :set_cluster_group, only: [:study, :show_user_annotations_form]
  before_action :set_selected_annotation, only: [:show_user_annotations_form]
  before_action :check_view_permissions, except: [:index, :legacy_study, :get_viewable_studies, :privacy_policy,
                                                  :terms_of_service, :log_action, :get_taxon, :get_taxon_assemblies,
                                                  :covid19, :record_download_acceptance, :reviewer_access,
                                                  :validate_reviewer_access]
  before_action :check_study_detached, only: [:download_file, :update_study_settings]
  before_action :set_reviewer_access, only: [:reviewer_access, :validate_reviewer_access]
  COLORSCALE_THEMES = %w(Greys YlGnBu Greens YlOrRd Bluered RdBu Reds Blues Picnic Rainbow Portland Jet Hot Blackbody Earth Electric Viridis Cividis)

  ###
  #
  # HOME & SEARCH METHODS
  #
  ###

  # view study overviews/descriptions
  def index

    # load viewable studies in requested order
    @viewable = Study.viewable(current_user).order_by(@order)

    # filter list if in branding group mode
    if @selected_branding_group.present?
      @viewable = @viewable.where(:branding_group_ids.in => [@selected_branding_group.id])
    end

    # determine study/cell count based on viewable to user
    @study_count = @viewable.count
    @cell_count = @viewable.map(&:cell_count).compact.inject(0, &:+)

    if @cell_count.nil?
      @cell_count = 0
    end

    @home_page_link = HomePageLink.published
  end

  def covid
    # nothing for now
  end

  # legacy method to load a study by url_safe_name, or simply by accession
  def legacy_study
    study = Study.any_of({url_safe_name: params[:identifier]},{accession: params[:identifier]}).first
    if study.present?
      fixed_path = RequestUtils.format_study_url(study, request.fullpath)
      redirect_to fixed_path and return
    else
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]),
                  alert: "You either do not have permission to perform that action, or #{params[:identifier]} does not exist.  #{SCP_SUPPORT_EMAIL}" and return
    end
  end

  def privacy_policy

  end

  def terms_of_service

  end

  ###
  #
  # STUDY SETTINGS
  #
  ###

  # re-render study description as CKEditor instance
  def edit_study_description

  end

  # update selected attributes via study settings tab
  def update_study_settings
    @spinner_target = '#update-study-settings-spinner'
    @modal_target = '#update-study-settings-modal'
    if !user_signed_in?
      set_study_default_options
      @notice = 'Please sign in before continuing.'
      render action: 'notice'
    else
      if @study.can_edit?(current_user)
        if @study.update(study_params)
          # invalidate caches as a precaution
          CacheRemovalJob.new(@study.accession).perform
          if @study.initialized?
            @cluster = @study.default_cluster
            @options = ClusterVizService.load_cluster_group_options(@study)
            @cluster_annotations = ClusterVizService.load_cluster_group_annotations(@study, @cluster, current_user)
            set_selected_annotation
          end
        end
        set_study_permissions(@study.detached?)
        set_study_default_options
        set_study_download_options

        # handle updates to reviewer access settings
        reviewer_access_actions = params.to_unsafe_hash['reviewer_access_actions']
        manage_reviewer_access(@study, reviewer_access_actions)
      else
        set_study_default_options
        @alert = 'You do not have permission to perform that action.'
        render action: 'notice'
      end
    end
  end

  ###
  #
  # VIEW/RENDER METHODS
  #
  ###

  ## CLUSTER-BASED

  # load single study and view top-level clusters
  def study
    # this skips all validation/callbacks for efficiency
    @study.update_attribute(:view_count, @study.view_count + 1)

    # set general state of study to enable various tabs in UI
    # double check on download availability: first, check if administrator has disabled downloads
    # then check individual statuses to see what to enable/disable
    # if the study is 'detached', then everything is set to false by default
    set_study_permissions(@study.detached?)
    set_study_default_options
    set_study_download_options

    # decide what tab to show by default for this user
    # normally we would do this in React but the tab display is in the Rails HTML view
    # we need to check server-side since we have to account for @study.can_visualize? as well
    @explore_tab_default = @study.can_visualize?
  end

  def record_download_acceptance
    @download_acceptance = DownloadAcceptance.new(download_acceptance_params)
    if @download_acceptance.save
      respond_to do |format|
        format.js
      end
    end
  end

  # reviewer access methods
  # @reviewer_access is loaded via :set_reviewer_access and will handle redirects on bad access_code values
  def reviewer_access
    @study = @reviewer_access.study
  end

  def validate_reviewer_access
    if @reviewer_access.authenticate_pin?(validate_reviewer_access_params[:pin])
      # create a new reviewer access session and redirect
      session = @reviewer_access.create_new_session
      study = @reviewer_access.study
      # write a signed cookie for use in validating auth
      cookies.signed[@reviewer_access.cookie_name] = {
        value: session.session_key,
        domain: ApplicationController.default_url_options[:host],
        expires: session.expires_at,
        secure: true,
        httponly: true,
        same_site: :strict
      }
      notice = "PIN successfully validated.  Your session is valid until #{session.expiration_time}"
      redirect_to merge_default_redirect_params(view_study_path(accession: study.accession,
                                                                study_name: study.url_safe_name),
                                                scpbr: params[:scpbr]), alert: nil, notice: notice
    else
      @study = @reviewer_access.study
      flash[:alert] = 'Invalid PIN - please try again.'
      render action: :reviewer_access, status: :forbidden
    end
  end

  ###
  #
  # DOWNLOAD METHODS
  #
  ###

  # method to download files if study is public
  def download_file
    # verify user can download file
    verify_file_download_permissions(@study); return if performed?
    # initiate file download action
    execute_file_download(@study); return if performed?
  end


  ###
  #
  # ANNOTATION METHODS
  #
  ###

  # render the 'Create Annotations' form (must be done via ajax to get around page caching issues)
  def show_user_annotations_form

  end

  ###
  #
  # MISCELLANEOUS METHODS
  #
  ###

  # route that is used to log actions in Google Analytics that would otherwise be ignored due to redirects or response types
  def log_action
    @action_to_log = params[:url_string]
  end

  # get taxon info
  def get_taxon
    @taxon = Taxon.find(params[:taxon])
    render json: @taxon.attributes
  end

  # get GenomeAssembly information for a given Taxon for StudyFile associations and other menu actions
  def get_taxon_assemblies
    @assemblies = []
    taxon = Taxon.find(params[:taxon])
    if taxon.present?
      @assemblies = taxon.genome_assemblies.map {|assembly| [assembly.name, assembly.id.to_s]}
    end
    render json: @assemblies
  end

  private

  ###
  #
  # SETTERS
  #
  ###

  def set_study
    @study = Study.find_by(accession: params[:accession])
    # redirect if study is not found
    if @study.nil?
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]),
                  alert: "You either do not have permission to perform that action, or #{params[:accession]} does not " \
                         "exist.  #{SCP_SUPPORT_EMAIL}" and return
    end
  end

  def set_cluster_group
    @cluster = ClusterVizService.get_cluster_group(@study, params)
  end

  def set_selected_annotation
    annot_params = ExpressionVizService.parse_annotation_legacy_params(@study, params)
    @selected_annotation = AnnotationVizService.get_selected_annotation(
      @study,
      cluster: @cluster,
      annot_name: annot_params[:name],
      annot_type: annot_params[:type],
      annot_scope: annot_params[:scope]
    )
  end

  def set_workspace_samples
    all_samples = ApplicationController.firecloud_client.get_workspace_entities_by_type(@study.firecloud_project, @study.firecloud_workspace, 'sample')
    @samples = Naturally.sort(all_samples.map {|s| s['name']})
    # load locations of primary data (for new sample selection)
    @primary_data_locations = []
    fastq_files = @study.study_files.by_type('Fastq').select {|f| !f.human_data}
    [fastq_files, @study.directory_listings.primary_data].flatten.each do |entry|
      @primary_data_locations << ["#{entry.name} (#{entry.description})", "#{entry.class.name.downcase}--#{entry.name}"]
    end
  end

  # set various study permissions based on the results of the above FC permissions
  def set_study_permissions(study_detached)
    @user_can_edit = false
    @user_can_compute = false
    @user_can_download = false
    @user_embargoed = false
    @allow_firecloud_access = AdminConfiguration.firecloud_access_enabled?

    return if study_detached || !@allow_firecloud_access
    begin
      @user_can_edit = @study.can_edit?(current_user)
      @user_can_download = @user_can_edit ? true : @study.can_download?(current_user)
      @user_embargoed = @user_can_edit ? false : @study.embargoed?(current_user)
    rescue => e
      logger.error "Error setting study permissions: #{e.class.name} -- #{e.message}"
      ErrorTracker.report_exception(e, current_user, @study)
      MetricsService.report_error(e, request, current_user, @study)
    end
  end

  # set all file download variables for study_download tab
  def set_study_download_options
    @study_files = @study.study_files.non_primary_data.sort_by(&:name)
    @primary_study_files = @study.study_files.primary_data
    @directories = @study.directory_listings.are_synced
    @primary_data = @study.directory_listings.primary_data
    @other_data = @study.directory_listings.non_primary_data

    # load download agreement/user acceptance, if present
    if @study.has_download_agreement?
      @download_agreement = @study.download_agreement
      @user_accepted_agreement = @download_agreement.user_accepted?(current_user)
    end
  end

  def set_reviewer_access
    @reviewer_access = ReviewerAccess.find_by(access_code: params[:access_code])
    unless @reviewer_access.present?
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]),
                  alert: 'Invalid access code; please check the link and try again.' and return
    end
  end

  # permit parameters for updating studies on study settings tab (smaller list than in studies controller)
  def study_params
    params.require(:study).permit(:name, :description, :public, :embargo, :cell_count,
                                  :default_options => [:cluster, :annotation, :color_profile, :expression_label,
                                                       :deliver_emails, :cluster_point_size, :cluster_point_alpha,
                                                       :cluster_point_border, :precomputed_heatmap_label,
                                                       :expression_sort, override_viz_limit_annotations: [],
                                                       cluster_order: [], spatial_order: []],
                                  study_shares_attributes: [:id, :_destroy, :email, :permission],
                                  study_detail_attributes: [:id, :full_description],
                                  reviewer_access_attributes: [:id, :expires_at],
                                  authors_attributes: [:id, :first_name, :last_name, :email, :institution,
                                                       :corresponding, :orcid, :_destroy],
                                  publications_attributes: [:id, :title, :journal, :citation, :url, :pmcid,
                                                            :preprint, :_destroy],
                                  external_resources_attributes: [:id, :_destroy, :title, :description, :url],
    )
  end

  # permit parameters for creating custom user annotation
  def user_annotation_params
    params.require(:user_annotation).permit(:_id, :name, :study_id, :user_id, :cluster_group_id, :subsample_threshold,
                                            :loaded_annotation, :subsample_annotation, user_data_arrays_attributes: [:name, :values])
  end

  def download_acceptance_params
    params.require(:download_acceptance).permit(:email, :download_agreement_id)
  end

  def validate_reviewer_access_params
    params.require(:reviewer_access).permit(:pin)
  end

  # make sure user has view permissions for selected study
  def check_view_permissions
    unless @study.public?
      if !user_signed_in? && @study.reviewer_access.present?
        reviewer = @study.reviewer_access
        session_key = cookies.signed[reviewer.cookie_name]
        if reviewer.expired?
          alert = 'The review period for this study has expired.'
          redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: alert and return
        elsif session_key.blank? # no cookie present, so this may or may not be a reviewer
          authenticate_user!
        elsif !reviewer.session_valid?(session_key) # check session cookie for expiry
          alert = 'Your review session has expired - please create a new session to continue.'
          redirect_to merge_default_redirect_params(reviewer_access_path(access_code: reviewer.access_code),
                                                    scpbr: params[:scpbr]), alert: alert and return
        end
      elsif !user_signed_in?
        authenticate_user!
      elsif user_signed_in? && !@study.can_view?(current_user)
        alert = "You do not have permission to perform that action.  #{SCP_SUPPORT_EMAIL}"
        redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: alert and return
      end
    end
  end

  # check compute permissions for study
  def check_compute_permissions
    if !user_signed_in? || !@study.can_compute?(current_user)
      @alert = "You do not have permission to perform that action.  #{SCP_SUPPORT_EMAIL}"
      respond_to do |format|
        format.js {render action: :notice}
        format.html {redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: @alert and return}
        format.json {head 403}
      end
    end
  end

  # check if a study is 'detached' from a workspace
  def check_study_detached
    if @study.detached?
      @alert = "We were unable to complete your request as #{@study.accession} is detached from the workspace " \
               "(maybe the workspace was deleted?).  #{SCP_SUPPORT_EMAIL}"
      respond_to do |format|
        format.js {render js: "alert('#{@alert}');"}
        format.html {redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: @alert and return}
        format.json {render json: {error: @alert}, status: 410}
      end
    end
  end

  # create a unique hex digest of a list of genes for use in set_cache_path
  def construct_gene_list_hash(query_list)
    genes = query_list.split(' ').map(&:strip).sort.join
    Digest::SHA256.hexdigest genes
  end

  # update sample table with contents of sample map
  def populate_rows(existing_list, file_list)
    # create hash of samples => array of reads
    sample_map = DirectoryListing.sample_read_pairings(file_list)
    sample_map.each do |sample, files|
      row = [sample]
      row += files
      # pad out row to make sure it has the correct number of entries (5)
      0.upto(4) {|i| row[i] ||= '' }
      existing_list << row
    end
  end

  # handle updates to reviewer access settings
  def manage_reviewer_access(study, access_settings)
    return if access_settings.blank?

    if access_settings['reset'] == 'yes'
      logger.info "Rotating credentials for reviewer access in #{study.accession}"
      study.reviewer_access.rotate_credentials! if study.reviewer_access.present?
    elsif access_settings['enable'] == 'yes' && study.reviewer_access.nil?
      logger.info "Initializing reviewer access in #{study.accession}"
      study.build_reviewer_access.save!
    elsif access_settings['enable'] == 'no'
      logger.info "Disabling reviewer access in #{study.accession}"
      study.reviewer_access.destroy if study.reviewer_access.present?
    end
  end
end
