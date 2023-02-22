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
                                     :view_workflow_wdl, :log_action, :get_taxon, :get_taxon_assemblies, :covid19,
                                     :reviewer_access, :validate_reviewer_access]
  before_action :set_cluster_group, only: [:study, :show_user_annotations_form]
  before_action :set_selected_annotation, only: [:show_user_annotations_form]
  before_action :check_view_permissions, except: [:index, :legacy_study, :get_viewable_studies, :privacy_policy,
                                                  :terms_of_service, :view_workflow_wdl, :log_action, :get_workspace_samples,
                                                  :update_workspace_samples, :get_workflow_options, :get_taxon,
                                                  :get_taxon_assemblies, :covid19, :record_download_acceptance,
                                                  :reviewer_access, :validate_reviewer_access]
  before_action :check_compute_permissions, only: [:get_fastq_files, :get_workspace_samples, :update_workspace_samples,
                                                   :delete_workspace_samples, :get_workspace_submissions, :create_workspace_submission,
                                                   :get_submission_workflow, :abort_submission_workflow, :get_submission_errors,
                                                   :get_submission_outputs, :delete_submission_files, :get_submission_metadata]
  before_action :check_study_detached, only: [:download_file, :update_study_settings,
                                              :get_fastq_files, :get_workspace_samples, :update_workspace_samples,
                                              :delete_workspace_samples, :get_workspace_submissions, :create_workspace_submission,
                                              :get_submission_workflow, :abort_submission_workflow, :get_submission_errors,
                                              :get_submission_outputs, :delete_submission_files, :get_submission_metadata]
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
    @cell_count = @viewable.map(&:cell_count).inject(&:+)

    if @cell_count.nil?
      @cell_count = 0
    end

  end

  def covid
    # nothing for now
  end

  # legacy method to load a study by url_safe_name, or simply by accession
  def legacy_study
    study = Study.any_of({url_safe_name: params[:identifier]},{accession: params[:identifier]}).first
    if study.present?
      redirect_to merge_default_redirect_params(view_study_path(accession: study.accession,
                                                                study_name: study.url_safe_name,
                                                                scpbr: params[:scpbr])) and return
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

          # double check on download availability: first, check if administrator has disabled downloads
          # then check if FireCloud is available and disable download links if either is true
          @allow_downloads = ApplicationController.firecloud_client.services_available?(FireCloudClient::BUCKETS_SERVICE)
        end
        set_firecloud_permissions(@study.detached?)
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
    set_firecloud_permissions(@study.detached?)
    set_study_permissions(@study.detached?)
    set_study_default_options
    set_study_download_options

    # decide what tab to show by default for this user
    # normally we would do this in React but the tab display is in the Rails HTML view
    # we need to check server-side since we have to account for @study.can_visualize? as well
    @explore_tab_default = @study.can_visualize? &&
                           AbTest.override_for_feature?('explore_tab_default', request.cookies['user_id'])
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
  # WORKFLOW METHODS
  #
  ###

  # method to populate an array with entries corresponding to all fastq files for a study (both owner defined as study_files
  # and extra fastq's that happen to be in the bucket)
  def get_fastq_files
    @fastq_files = []
    file_list = []

    #
    selected_entries = params[:selected_entries].split(',').map(&:strip)
    selected_entries.each do |entry|
      class_name, entry_name = entry.split('--')
      case class_name
        when 'directorylisting'
          directory = @study.directory_listings.are_synced.detect {|d| d.name == entry_name}
          if !directory.nil?
            directory.files.each do |file|
              entry = file
              entry[:gs_url] = directory.gs_url(file[:name])
              file_list << entry
            end
          end
        when 'studyfile'
          study_file = @study.study_files.by_type('Fastq').detect {|f| f.name == entry_name}
          if !study_file.nil?
            file_list << {name: study_file.bucket_location, size: study_file.upload_file_size, generation: study_file.generation, gs_url: study_file.gs_url}
          end
        else
          nil # this is called when selection is cleared out
      end
    end
    # now that we have the complete list, populate the table with sample pairs (if present)
    populate_rows(@fastq_files, file_list)

    render json: @fastq_files.to_json
  end

  # view the wdl of a specified workflow
  def view_workflow_wdl
    analysis_configuration = AnalysisConfiguration.find_by(namespace: params[:namespace], name: params[:workflow],
                                                                              snapshot: params[:snapshot].to_i)
    @workflow_name = analysis_configuration.name
    @workflow_wdl = analysis_configuration.wdl_payload
  end

  # get the available entities for a workspace
  def get_workspace_samples
    begin
      requested_samples = params[:samples].split(',')
      # get all samples
      all_samples = ApplicationController.firecloud_client.get_workspace_entities_by_type(@study.firecloud_project, @study.firecloud_workspace, 'sample')
      # since we can't query the API (easily) for matching samples, just get all and then filter based on requested samples
      matching_samples = all_samples.keep_if {|sample| requested_samples.include?(sample['name']) }
      @samples = []
      matching_samples.each do |sample|
        @samples << [sample['name'],
                     sample['attributes']['fastq_file_1'],
                     sample['attributes']['fastq_file_2'],
                     sample['attributes']['fastq_file_3'],
                     sample['attributes']['fastq_file_4']
        ]
      end
      render json: @samples.to_json
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "Error retrieving workspace samples for #{study.name}; #{e.message}"
      render json: []
    end
  end

  # save currently selected sample information back to study workspace
  def update_workspace_samples
    form_payload = params[:samples]

    begin
      # create a 'real' temporary file as we can't pass open tempfiles
      filename = "#{SecureRandom.uuid}-sample-info.tsv"
      temp_tsv = File.new(Rails.root.join('data', @study.data_dir, filename), 'w+')

      # add participant_id to new file as FireCloud data model requires this for samples (all samples get default_participant value)
      headers = %w(entity:sample_id participant_id fastq_file_1 fastq_file_2 fastq_file_3 fastq_file_4)
      temp_tsv.write headers.join("\t") + "\n"

      # get list of samples from form payload
      samples = form_payload.keys
      samples.each do |sample|
        # construct a new line to write to the tsv file
        newline = "#{sample}\tdefault_participant\t"
        vals = []
        headers[2..5].each do |attr|
          # add a value for each parameter, created an empty string if this was not present in the form data
          vals << form_payload[sample][attr].to_s
        end
        # write new line to tsv file
        newline += vals.join("\t")
        temp_tsv.write newline + "\n"
      end
      # close the file to ensure write is completed
      temp_tsv.close

      # now reopen and import into FireCloud
      upload = File.open(temp_tsv.path)
      ApplicationController.firecloud_client.import_workspace_entities_file(@study.firecloud_project, @study.firecloud_workspace, upload)

      # upon success, load the newly imported samples from the workspace and update the form
      new_samples = ApplicationController.firecloud_client.get_workspace_entities_by_type(@study.firecloud_project, @study.firecloud_workspace, 'sample')
      @samples = Naturally.sort(new_samples.map {|s| s['name']})

      # clean up tempfile
      File.delete(temp_tsv.path)

      # render update notice
      @notice = 'Your sample information has successfully been saved.'
      render action: :update_workspace_samples
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      logger.info "Error saving workspace entities: #{e.message}"
      @alert = "An error occurred while trying to save your sample information: #{view_context.simple_format(e.message)}"
      render action: :notice
    end
  end

  # delete selected samples from workspace data entities
  def delete_workspace_samples
    samples = params[:samples]
    begin
      # create a mapping of samples to delete
      delete_payload = ApplicationController.firecloud_client.create_entity_map(samples, 'sample')
      ApplicationController.firecloud_client.delete_workspace_entities(@study.firecloud_project, @study.firecloud_workspace, delete_payload)

      # upon success, load the newly imported samples from the workspace and update the form
      new_samples = ApplicationController.firecloud_client.get_workspace_entities_by_type(@study.firecloud_project, @study.firecloud_workspace, 'sample')
      @samples = Naturally.sort(new_samples.map {|s| s['name']})

      # render update notice
      @notice = 'The requested samples have successfully been deleted.'

      # set flag to empty out the samples table to prevent the user from trying to delete the sample again
      @empty_samples_table = true
      render action: :update_workspace_samples
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "Error deleting workspace entities: #{e.message}"
      @alert = "An error occurred while trying to delete your sample information: #{view_context.simple_format(e.message)}"
      render action: :notice
    end
  end

  # get all submissions for a study workspace
  def get_workspace_submissions
    @submissions = TerraAnalysisService.list_submissions(@study)
  end

  # retrieve analysis configuration and associated parameters
  def get_analysis_configuration
    namespace, name, snapshot = params[:workflow_identifier].split('--')
    @analysis_configuration = AnalysisConfiguration.find_by(namespace: namespace, name: name,
                                                           snapshot: snapshot.to_i)
  end

  def create_workspace_submission
    begin
      # before creating submission, we need to make sure that the user is on the 'all-portal' user group list if it exists
      current_user.add_to_portal_user_group

      # load analysis configuration
      @analysis_configuration = AnalysisConfiguration.find(params[:analysis_configuration_id])


      logger.info "Updating configuration for #{@analysis_configuration.configuration_identifier} to run #{@analysis_configuration.identifier} in #{@study.firecloud_project}/#{@study.firecloud_workspace}"
      submission_config = @analysis_configuration.apply_user_inputs(params[:workflow][:inputs])
      # save configuration in workspace
      ApplicationController.firecloud_client.create_workspace_configuration(@study.firecloud_project, @study.firecloud_workspace, submission_config)

      # submission must be done as user, so create a client with current_user and submit
      client = FireCloudClient.new(current_user, @study.firecloud_project)
      logger.info "Creating submission for #{@analysis_configuration.configuration_identifier} using configuration: #{submission_config['name']} in #{@study.firecloud_project}/#{@study.firecloud_workspace}"
      @submission = client.create_workspace_submission(@study.firecloud_project, @study.firecloud_workspace,
                                                         submission_config['namespace'], submission_config['name'],
                                                         submission_config['entityType'], submission_config['entityName'])
      AnalysisSubmission.create(submitter: current_user.email, study_id: @study.id, firecloud_project: @study.firecloud_project,
                                submission_id: @submission['submissionId'], firecloud_workspace: @study.firecloud_workspace,
                                analysis_name: @analysis_configuration.identifier, submitted_on: Time.zone.now, submitted_from_portal: true)
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "Unable to submit workflow #{@analysis_configuration.identifier} in #{@study.firecloud_workspace} due to: #{e.message}"
      @alert = "We were unable to submit your workflow due to an error: #{e.message}"
      render action: :notice
    end
  end

  # get a submission workflow object as JSON
  def get_submission_workflow
    begin
      submission = ApplicationController.firecloud_client.get_workspace_submission(@study.firecloud_project, @study.firecloud_workspace, params[:submission_id])
      render json: submission.to_json
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "Unable to load workspace submission #{params[:submission_id]} in #{@study.firecloud_workspace} due to: #{e.message}"
      render js: "alert('We were unable to load the requested submission due to an error: #{e.message}')"
    end
  end

  # abort a pending workflow submission
  def abort_submission_workflow
    @submission_id = params[:submission_id]
    begin
      ApplicationController.firecloud_client.abort_workspace_submission(@study.firecloud_project, @study.firecloud_workspace, @submission_id)
      @notice = "Submission #{@submission_id} was successfully aborted."
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      @alert = "Unable to abort submission #{@submission_id} due to an error: #{e.message}"
      render action: :notice
    end
  end

  # get errors for a failed submission
  def get_submission_errors
    begin
      workflow_ids = params[:workflow_ids].split(',')
      errors = []
      # first check workflow messages - if there was an issue with inputs, errors could be here
      submission = ApplicationController.firecloud_client.get_workspace_submission(@study.firecloud_project, @study.firecloud_workspace, params[:submission_id])
      submission['workflows'].each do |workflow|
        if workflow['messages'].any?
          workflow['messages'].each {|message| errors << message}
        end
      end
      # now look at each individual workflow object
      workflow_ids.each do |workflow_id|
        workflow = ApplicationController.firecloud_client.get_workspace_submission_workflow(@study.firecloud_project, @study.firecloud_workspace, params[:submission_id], workflow_id)
        # failure messages are buried deeply within the workflow object, so we need to go through each to find them
        workflow['failures'].each do |workflow_failure|
          errors << workflow_failure['message']
          # sometimes there are extra errors nested below...
          if workflow_failure['causedBy'].any?
            workflow_failure['causedBy'].each do |failure|
              errors << failure['message']
            end
          end
        end
      end
      @error_message = errors.join("<br />")
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      @alert = "Unable to retrieve submission #{@submission_id} error messages due to: #{e.message}"
      render action: :notice
    end
  end

  # get outputs from a requested submission
  def get_submission_outputs
    begin
      @outputs = []
      submission = ApplicationController.firecloud_client.get_workspace_submission(@study.firecloud_project, @study.firecloud_workspace, params[:submission_id])
      submission['workflows'].each do |workflow|
        workflow = ApplicationController.firecloud_client.get_workspace_submission_workflow(@study.firecloud_project, @study.firecloud_workspace, params[:submission_id], workflow['workflowId'])
        workflow['outputs'].each do |output, file_url|
          display_name = file_url.split('/').last
          file_location = file_url.gsub(/gs\:\/\/#{@study.bucket_id}\//, '')
          output = {display_name: display_name, file_location: file_location}
          @outputs << output
        end
      end
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      @alert = "Unable to retrieve submission #{@submission_id} outputs due to: #{e.message}"
      render action: :notice
    end
  end

  # retrieve a submission analysis metadata file
  def get_submission_metadata
    begin
      submission = ApplicationController.firecloud_client.get_workspace_submission(@study.firecloud_project, @study.firecloud_workspace, params[:submission_id])
      if submission.present?
        # check to see if we already have an analysis_metadatum object
        @metadata = AnalysisMetadatum.find_by(study_id: @study.id, submission_id: params[:submission_id])
        if @metadata.nil?
          metadata_attr = {
              name: submission['methodConfigurationName'],
              submission_id: params[:submission_id],
              study_id: @study.id,
              version: '4.6.1'
          }
          @metadata = AnalysisMetadatum.create!(metadata_attr)
        end
      else
        @alert = "We were unable to locate submission '#{params[:submission_id]}'.  Please check the ID and try again."
        render action: :notice
      end
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      @alert = "An error occurred trying to load submission '#{params[:submission_id]}': #{e.message}"
      render action: :notice
    end
  end

  # export a submission analysis metadata file
  def export_submission_metadata
    @metadata = AnalysisMetadatum.find_by(study_id: @study.id, submission_id: params[:submission_id])
    respond_to do |format|
      format.html {send_data JSON.pretty_generate(@metadata.payload), content_type: :json, filename: 'analysis.json'}
      format.json {render json: @metadata.payload}
    end

  end

  # delete all files from a submission
  def delete_submission_files
    begin
      # first, add submission to list of 'deleted_submissions' in workspace attributes (will hide submission in list)
      workspace = ApplicationController.firecloud_client.get_workspace(@study.firecloud_project, @study.firecloud_workspace)
      ws_attributes = workspace['workspace']['attributes']
      if ws_attributes['deleted_submissions'].blank?
        ws_attributes['deleted_submissions'] = [params[:submission_id]]
      else
        ws_attributes['deleted_submissions']['items'] << params[:submission_id]
      end
      logger.info "Adding #{params[:submission_id]} to workspace delete_submissions attribute in #{@study.firecloud_workspace}"
      ApplicationController.firecloud_client.set_workspace_attributes(@study.firecloud_project, @study.firecloud_workspace, ws_attributes)
      logger.info "Deleting analysis metadata for #{params[:submission_id]} in #{@study.url_safe_name}"
      AnalysisMetadatum.where(submission_id: params[:submission_id]).delete
      logger.info "Queueing submission #{params[:submission]} deletion in #{@study.firecloud_workspace}"
      submission_files = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_files, 0, @study.bucket_id, prefix: params[:submission_id])
      DeleteQueueJob.new(submission_files).perform
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "Unable to remove submission #{params[:submission_id]} files from #{@study.firecloud_workspace} due to: #{e.message}"
      @alert = "Unable to delete the outputs for #{params[:submission_id]} due to the following error: #{e.message}"
      render action: :notice
    end
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
    # Check if current url_safe_name matches model
    unless @study.url_safe_name == params[:study_name]
      redirect_to merge_default_redirect_params(view_study_path(accession: params[:accession],
                                                                study_name: @study.url_safe_name,
                                                                scpbr:params[:scpbr])) and return
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

  # check various firecloud statuses/permissions, but only if a study is not 'detached'
  def set_firecloud_permissions(study_detached)
    @allow_firecloud_access = false
    @allow_downloads = false
    @allow_edits = false
    return if study_detached
    begin
      @allow_firecloud_access = AdminConfiguration.firecloud_access_enabled?
      api_status = ApplicationController.firecloud_client.api_status
      # reuse status object because firecloud_client.services_available? each makes a separate status call
      # calling Hash#dig will gracefully handle any key lookup errors in case of a larger outage
      if api_status.is_a?(Hash)
        system_status = api_status['systems']
        sam_ok = system_status.dig(FireCloudClient::SAM_SERVICE, 'ok') == true # do equality check in case 'ok' node isn't present
        rawls_ok = system_status.dig(FireCloudClient::RAWLS_SERVICE, 'ok') == true
        buckets_ok = system_status.dig(FireCloudClient::BUCKETS_SERVICE, 'ok') == true
        @allow_downloads = buckets_ok
        @allow_edits = sam_ok && rawls_ok
      end
    rescue => e
      logger.error "Error checking FireCloud API status: #{e.class.name} -- #{e.message}"
      ErrorTracker.report_exception(e, current_user, @study, { firecloud_status: api_status})
      MetricsService.report_error(e, request, current_user, @study)
    end
  end

  # set various study permissions based on the results of the above FC permissions
  def set_study_permissions(study_detached)
    @user_can_edit = false
    @user_can_compute = false
    @user_can_download = false
    @user_embargoed = false

    return if study_detached || !@allow_firecloud_access
    begin
      @user_can_edit = @study.can_edit?(current_user)
      if @allow_downloads
        @user_can_download = @user_can_edit ? true : @study.can_download?(current_user)
        @user_embargoed = @user_can_edit ? false : @study.embargoed?(current_user)
      end
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
                                                       override_viz_limit_annotations: []],
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
    if ApplicationController.firecloud_client.services_available?(FireCloudClient::SAM_SERVICE, FireCloudClient::RAWLS_SERVICE)
      if !user_signed_in? || !@study.can_compute?(current_user)
        @alert = "You do not have permission to perform that action.  #{SCP_SUPPORT_EMAIL}"
        respond_to do |format|
          format.js {render action: :notice}
          format.html {redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: @alert and return}
          format.json {head 403}
        end
      end
    else
      @alert = "Compute services are currently unavailable - please check back later.  #{SCP_SUPPORT_EMAIL}"
      respond_to do |format|
        format.js {render action: :notice}
        format.html {redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: @alert and return}
        format.json {head 503}
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

  # load list of available workflows
  def load_available_workflows
    AnalysisConfiguration.available_analyses
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
