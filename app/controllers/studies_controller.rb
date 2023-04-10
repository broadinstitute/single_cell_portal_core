class StudiesController < ApplicationController

  ###
  #
  # This is the main study creation controller.  Handles CRUDing studies, uploading & parsing files, and syncing to workspaces
  #
  ###

  ###
  #
  # FILTERS & SETTINGS
  #
  ###

  respond_to :html, :js, :json

  before_action :set_study, except: [:index, :new, :create, :download_private_file]
  before_action :set_file_types, only: [:sync_study, :sync_submission_outputs, :sync_study_file, :sync_orphaned_study_file,
                                        :update_study_file_from_sync]
  before_action :check_edit_permissions, except: [:index, :new, :create, :download_private_file, :generate_manifest]
  before_action do
    authenticate_user!
    check_access_settings
  end
  # special before_action to make sure FireCloud is available and pre-empt any calls when down
  before_action :check_firecloud_status, except: [:index, :do_upload, :resume_upload, :update_status,
                                                  :retrieve_wizard_upload, :parse]
  before_action :check_study_detached, only: [:edit, :update, :initialize_study, :sync_study, :sync_submission_outputs]
  helper_method :visible_unsynced_files, :hidden_unsynced_files
  ###
  #
  # STUDY OBJECT METHODS
  #
  ###

  # GET /studies
  # GET /studies.json
  def index
    @studies = Study.accessible(current_user).to_a
  end

  # GET /studies/1
  # GET /studies/1.json
  def show
    @study_fastq_files = @study.study_files.primary_data
    @directories = @study.directory_listings.are_synced
    @primary_data = @study.directory_listings.primary_data
    @other_data = @study.directory_listings.non_primary_data
    @allow_downloads = ApplicationController.firecloud_client.services_available?(FireCloudClient::BUCKETS_SERVICE) && !@study.detached
    @analysis_metadata = @study.analysis_metadata.to_a
    # load study default options
    set_study_default_options
  end

  # GET /studies/new
  def new
    @study = Study.new
    @study.build_study_detail

    # load the given user's available FireCloud billing projects
    set_user_projects
  end

  # GET /studies/1/edit
  def edit
    set_user_projects
  end

  # POST /studies
  # POST /studies.json
  def create
    @study = Study.new(study_params)

    respond_to do |format|
      if @study.save
        path = @study.use_existing_workspace ? sync_study_path(@study) : initialize_study_path(@study)
        format.html { redirect_to merge_default_redirect_params(path, scpbr: params[:scpbr]),
                                  notice: "Your study '#{@study.name}' was successfully created." }
        format.json { render :show, status: :ok, location: @study }
      else
        @study.build_study_detail
        set_user_projects
        format.html { render :new }
        format.json { render json: @study.errors, status: :unprocessable_entity }
      end
    end
  end

  # wizard for adding study files after user creates a study
  def initialize_study
    # load any existing files if user restarted for some reason (unlikely)
    initialize_wizard_files
    # check if study has been properly initialized yet, set to true if not
    if !@cluster_ordinations.last.new_record? && !@processed_matrix_files.last.new_record? && !@metadata_file.new_record? && !@study.initialized?
      @study.update_attributes(initialized: true)
    end
  end

  # allow a user to sync files uploaded outside the portal into a workspace bucket with an existing study
  def sync_study
    @study_files = @study.study_files.available
    @study_files.each { |study_file| study_file.build_expression_file_info if study_file.expression_file_info.nil? }

     # first sync permissions if necessary
    begin
      @permissions_changed = StudySyncService.update_shares_from_acl(@study)
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "Error syncing ACLs in workspace bucket #{@study.firecloud_workspace} due to error: #{e.message}"
      redirect_to merge_default_redirect_params(studies_path, scpbr: params[:scpbr]),
                  alert: "We were unable to sync with your workspace bucket due to an error: #{view_context.simple_format(e.message)}.  #{SCP_SUPPORT_EMAIL}" and return
    end

    # begin determining sync status with study_files and primary or other data
    begin
      @unsynced_files = StudySyncService.process_all_remotes(@study)
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "#{Time.zone.now}: error syncing files in workspace bucket #{@study.firecloud_workspace} due to error: #{e.message}"
      redirect_to merge_default_redirect_params(studies_path, scpbr: params[:scpbr]),
                  alert: "We were unable to sync with your workspace bucket due to an error: #{view_context.simple_format(e.message)}.  #{SCP_SUPPORT_EMAIL}" and return
    end

    # refresh study state before continuing as new records may have been inserted
    @study.reload
    @synced_directories = @study.directory_listings.are_synced
    @unsynced_directories = @study.directory_listings.unsynced

    # split directories into primary data types and 'others'
    @unsynced_primary_data_dirs, @unsynced_other_dirs = StudySyncService.load_unsynced_directories(@study)

    # now determine if we have study_files that have been 'orphaned' (cannot find a corresponding bucket file)
    @orphaned_study_files = StudySyncService.find_orphaned_files(@study)
    @available_files = StudySyncService.set_available_files(@unsynced_files)
    @synced_study_files = StudySyncService.set_synced_files(@study, @orphaned_study_files)
  end

  # sync outputs from a specific submission
  def sync_submission_outputs
    @synced_study_files = @study.study_files.valid
    @synced_directories = @study.directory_listings.to_a
    @unsynced_files = []
    @orphaned_study_files = []
    @unsynced_primary_data_dirs = []
    @unsynced_other_dirs = []
    configuration_name = params[:configuration_name]
    configuration_namespace = params[:configuration_namespace]
    begin
      # indication of whether or not we have custom sync code to run, defaults to false
      @special_sync = false
      configuration = ApplicationController.firecloud_client.get_workspace_configuration(@study.firecloud_project, @study.firecloud_workspace,
                                                                         configuration_namespace, configuration_name)
      submission = ApplicationController.firecloud_client.get_workspace_submission(@study.firecloud_project, @study.firecloud_workspace,
                                                                   params[:submission_id])
      # get method identifiers to load analysis_configuration object
      method_name = configuration['methodRepoMethod']['methodName']
      method_namespace = configuration['methodRepoMethod']['methodNamespace']
      method_snapshot = configuration['methodRepoMethod']['methodVersion']
      @analysis_configuration = AnalysisConfiguration.find_by(namespace: method_namespace, name: method_name, snapshot: method_snapshot)
      if @analysis_configuration.present?
        @special_sync = true
      end
      submission['workflows'].each do |workflow|
        workflow = ApplicationController.firecloud_client.get_workspace_submission_workflow(@study.firecloud_project, @study.firecloud_workspace,
                                                                            params[:submission_id], workflow['workflowId'])
        workflow['outputs'].each do |output_name, outputs|
          # try to copy each 'output' to the special output path if the object is a file
          # if the output is not a file, then we exit silently rather than throwing an error
          if outputs.is_a?(Array)
            outputs.each do |output_file|
              file_location = output_file.gsub(/gs\:\/\/#{@study.bucket_id}\//, '')
              # get google instance of file
              remote_file = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, @study.bucket_id, file_location)
              if remote_file.present?
                process_workflow_output(output_name, output_file, remote_file, workflow, params[:submission_id], configuration)
              end
            end
          elsif outputs.is_a?(String)
            file_location = outputs.gsub(/gs\:\/\/#{@study.bucket_id}\//, '')
            # get google instance of file
            remote_file = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, @study.bucket_id, file_location)
            if remote_file.present?
              process_workflow_output(output_name, outputs, remote_file, workflow, params[:submission_id], configuration)
            end
          else
            next # optional outputs can be nil so ignore
          end
        end
        metadata = AnalysisMetadatum.find_by(study_id: @study.id, submission_id: params[:submission_id])
        if metadata.nil?
          metadata_attr = {
              name: submission['methodConfigurationName'],
              submitter: submission['submitter'],
              submission_id: params[:submission_id],
              study_id: @study.id,
              version: '4.6.1'
          }
          begin
            AnalysisMetadatum.create(metadata_attr)
          rescue => e
            ErrorTracker.report_exception(e, current_user, @study, params, { analysis_metadata: metadata_attr})
            MetricsService.report_error(e, request, current_user, @study)
            logger.error "Unable to create analysis metadatum for #{params[:submission_id]}: #{e.class.name}:: #{e.message}"
          end
        end
      end
      @available_files = @unsynced_files.map {|f| {name: f.name, generation: f.generation, size: f.upload_file_size}}
      render action: :sync_study
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      redirect_to merge_default_redirect_params(request.referrer, scpbr: params[:scpbr]),
                  alert: "We were unable to sync the outputs from submission #{params[:submission_id]} due to the " \
                         "following error: #{e.message}.  #{SCP_SUPPORT_EMAIL}"
    end
  end

  # PATCH/PUT /studies/1
  # PATCH/PUT /studies/1.json
  def update
    # check if any changes were made to sharing for notifications
    if !study_params[:study_shares_attributes].nil?
      @share_changes = @study.study_shares.count != study_params[:study_shares_attributes].keys.size
      study_params[:study_shares_attributes].values.each do |share|
        if share["_destroy"] == "1"
          @share_changes = true
        end
      end
    else
      set_user_projects
      @share_changes = false
    end

    respond_to do |format|
      if @study.update(study_params)

        # if user updates a study, invalidate all caches
        CacheRemovalJob.new(@study.accession).delay(queue: :cache).perform

        changes = @study.previous_changes.delete_if {|k,v| k == 'updated_at'}.keys.map {|k| k.humanize.capitalize}
        if @share_changes == true
          changes << 'Study shares'
        end

        if @study.study_shares.any?
          SingleCellMailer.share_update_notification(@study, changes, current_user).deliver_now
        end
        format.html { redirect_to merge_default_redirect_params(studies_path, scpbr: params[:scpbr]), notice: "Study '#{@study.name}' was successfully updated." }
        format.json { render :show, status: :ok, location: @study }
      else
        format.html { render :edit }
        format.json { render json: @study.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /studies/1
  # DELETE /studies/1.json
  def destroy
    # check if user is allowed to delete study
    if @study.can_delete?(current_user)
      name = @study.name
      ### DESTROY PROCESS FOR PORTAL
      #
      # Studies are not deleted on-demand due to memory performance.  Instead, studies are queued for deletion and
      # destroyed nightly after the database has been re-indexed.  This uses less memory and also makes the process
      # faster for end users

      # set queued_for_deletion manually - gotcha due to race condition on page reloading and how quickly delayed_job can process jobs
      @study.update(queued_for_deletion: true)

      # delete firecloud workspace so it can be reused (unless specified by user), and raise error if unsuccessful
      # if successful, we're clear to queue the study for deletion
      # if a study is detached, then force the 'persist' option as it will fail otherwise
      if params[:workspace] == 'persist' || @study.detached
        @study.update(firecloud_workspace: SecureRandom.uuid)
      else
        begin
          ApplicationController.firecloud_client.delete_workspace(@study.firecloud_project, @study.firecloud_workspace)
        rescue => e
          ErrorTracker.report_exception(e, current_user, @study, params)
          MetricsService.report_error(e, request, current_user, @study)
          logger.error "Unable to delete workspace: #{@study.firecloud_workspace}; #{e.message}"
          redirect_to merge_default_redirect_params(studies_path, scpbr: params[:scpbr]),
                      alert: "We were unable to delete your study due to: #{view_context.simple_format(e.message)}.<br />" \
                             "<br />No files or database records have been deleted.  Please try again later.  #{SCP_SUPPORT_EMAIL}" and return
        end
      end

      # queue jobs to delete study caches & study itself
      CacheRemovalJob.new(@study.accession).delay(queue: :cache).perform
      DeleteQueueJob.new(@study).delay.perform

      # notify users of deletion before removing shares & owner
      SingleCellMailer.study_delete_notification(@study, current_user).deliver_now

      # revoke all study_shares
      @study.study_shares.delete_all
      update_message = "Study '#{name}'was successfully deleted. All #{params[:workspace].blank? ? 'workspace data & ' : nil}portal records have been removed as well."

      respond_to do |format|
        format.html { redirect_to merge_default_redirect_params(studies_path, scpbr: params[:scpbr]), notice: update_message }
        format.json { head :no_content }
      end
    else
      redirect_to merge_default_redirect_params(studies_path, scpbr: params[:scpbr]),
                  alert: "You do not have permission to perform that action.  #{SCP_SUPPORT_EMAIL}" and return
    end
  end

  ###
  #
  # STUDYFILE OBJECT METHODS
  #
  ###

  # create a new study_file for requested study
  def new_study_file
    file_type = params[:file_type] ? params[:file_type] : 'Cluster'
    @study_file = @study.build_study_file({file_type: file_type})
    @study_file.build_expression_file_info if @study_file.is_expression?
    if params[:taxon_id]
      taxon = Taxon.find(params[:taxon_id])
      @study_file.taxon_id = taxon.id if taxon.present?
    end
    if params[:is_raw_counts]
      raw_counts_val = params[:is_raw_counts] == 'true'
      @study_file.expression_file_info.is_raw_counts = raw_counts_val
    end
    @allow_only = params[:allow_only] ? params[:allow_only] : 'all'
  end

  # method to perform chunked uploading of data
  def do_upload
    upload = get_upload
    # remove spaces and + (encoded space character) from filename since this converted client-side,
    # but original_filename is unchanged in headers
    # if this method is being called manually (like in a test) this may not have happened, so look for both filenames
    filename = upload.original_filename.gsub(CarrierWave::SanitizedFile.sanitize_regexp, '_')
    study_file = @study.study_files.detect {|sf| [filename, upload.original_filename].include? sf.upload_file_name}
    # If no file has been uploaded or the uploaded file has a different filename,
    # do a new upload from scratch
    if study_file.nil?
      # don't use helper as we're about to mass-assign params
      study_file = @study.study_files.build
      begin
        study_file.update!(study_file_params)
      rescue => e
        logger.error "#{study_file.errors.full_messages.join(", ")}"
        existing_file = StudyFile.find(study_file.id)
        if existing_file
          ErrorTracker.report_exception(e, current_user, params)
          MetricsService.report_error(e, request, current_user, @study)
          logger.error("do_upload Failed: Existing file for #{study_file.id} -- type:#{existing_file.file_type} name:#{existing_file.name}")
        end
        render json: { file: { name: study_file.upload_file_name, errors: study_file.errors.full_messages.join(", ") } }, status: 422 and return
      end
      # determine if we need to create a study_file_bundle for the new study_file
      if StudyFileBundle::BUNDLE_TYPES.include?(study_file.file_type) && study_file.file_type != 'Cluster'
        matching_bundle = @study.study_file_bundles.detect {|bundle| bundle.bundle_type == study_file.file_type && bundle.parent == study_file}
        if matching_bundle.nil?
          study_file_bundle = @study.study_file_bundles.build(bundle_type: study_file.file_type)
          bundle_payload = StudyFileBundle.generate_file_list(study_file)
          study_file_bundle.original_file_list = bundle_payload
          study_file_bundle.save! # saving the study_file_bundle will create new placeholder entries for the bundled study_files
        end
      end
      # we need to add this file to a study_file_bundle if it was assigned
      if study_file_params[:study_file_bundle_id].present?
        # we're processing a bundled upload, which means there might be a placeholder file entry we need to find
        study_file_bundle = StudyFileBundle.find_by(study_id: @study.id, id: study_file_params[:study_file_bundle_id])
        file_type = study_file.file_type
        # ignore if this is the parent file
        unless file_type == study_file_bundle.bundle_type
          study_file_bundle.add_files(study_file)
        end
      end
      render json: { file: { name: study_file.upload_file_name,size: upload.size } } and return
    else
      current_size = study_file.upload_file_size
      content_range = request.headers['CONTENT-RANGE']
      if content_range.present? # we might not have this if this is a bundled upload, meaning the study_file was already present
        begin_of_chunk = content_range[/\ (.*?)-/,1].to_i # "bytes 100-999999/1973660678" will return '100'

        # If the there is a mismatch between the size of the incomplete upload and the content-range in the
        # headers, then it's the wrong chunk!
        # In this case, start the upload from scratch
        unless begin_of_chunk == current_size
          render json: study_file.to_jq_upload and return
        end
      end
      # Add the following chunk to the incomplete upload, converting to unix line endings
      File.open(study_file.upload.path, "ab") do |f|
        f.write upload.read
      end

      # Update the upload_file_size attribute
      study_file.upload_file_size = study_file.upload_file_size.nil? ? upload.size : study_file.upload_file_size + upload.size
      study_file.save!

      render json: study_file.to_jq_upload and return
    end
  end

  # GET /courses/:id/resume_upload.json
  def resume_upload
    study_file = StudyFile.where(study_id: params[:id], upload_file_name: params[:file]).first
    if study_file.nil?
      render json: { file: { name: "/uploads/default/missing.png",size: nil } } and return
    elsif study_file.status == 'uploaded'
      render json: {file: nil } and return
    else
      render json: { file: { name: study_file.upload.url, size: study_file.upload_file_size } } and return
    end
  end

  # update a study_file's upload status to 'uploaded'
  def update_status
    study_file = StudyFile.find_by(study_id: params[:id], upload_file_name: params[:file])
    if study_file.present?
      study_file.update!(status: params[:status])
      head :ok
    else
      head :not_found
    end
  end

  # retrieve study file by filename during initializer wizard
  def retrieve_wizard_upload
    @study_file = StudyFile.find_by(study_id: params[:id], upload_file_name: params[:file])
    if @study_file.nil?
      head 404 and return
    end
    @bundled_files = {}
    # determine if we need to add forms to the page for bundled files
    if StudyFileBundle::BUNDLE_TYPES.include?(@study_file.file_type) && @study_file.file_type != 'Cluster'
      @study_file_bundle = @study_file.study_file_bundle.present? ? @study_file.study_file_bundle : @study.study_file_bundles.build(bundle_type: @study_file.file_type)
      # initialize container that will be used to render new forms in the upload wizard if needed
      target = @study_file.form_container_id
      @bundled_files[target] = []
      StudyFileBundle::BUNDLE_REQUIREMENTS[@study_file.file_type].each do |bundled_file_type|
        if @study_file_bundle.bundled_files.detect {|f| f.file_type == bundled_file_type}.nil?
          @bundled_files[target] << @study.study_files.build(file_type: bundled_file_type, study_file_bundle_id: @study_file_bundle.id)
        end
      end
    end
    # determine state for processed matrix overlay
    set_expression_form_state
  end

  # begin uploading a bundled study_file while parent is still uploading
  def initialize_bundled_file
    parent_file = StudyFile.find_by(study_id: params[:id], id: params[:study_file_id])
    if parent_file.present? && parent_file.study_file_bundle.present?
      @bundle = parent_file.study_file_bundle
      # either load existing bundled file, or create new one of the requested file_type
      @study_file = @bundle.bundled_files.detect {|f| f.file_type == params[:file_type] }
      if @study_file.nil?
        @study_file = @study.study_files.build(study_file_bundle_id: @bundle.id, file_type: params[:file_type])
      end
      @target = parent_file.form_container_id
    else
      alert = 'Invalid operation: you cannot bundle files with the requested study file.'
      respond_to do |format|
        format.html {head 422}
        format.json {render json: {error: alert}, status: 422}
        format.js {render js: "alert('#{alert}');"}
      end
    end
  end

  # parses happen in background to prevent UI blocking
  def parse
    @study_file = StudyFile.where(study_id: params[:id], upload_file_name: params[:file]).first
    @status = FileParseService.run_parse_job(@study_file, @study, current_user)
    @allow_only = params[:allow_only] || 'all'
    # special handling for coordinate labels
    if @study_file.file_type == 'Coordinate Labels' && @status[:status_code] == 412
      # delete file and inform user of issue as this error is not recoverable
      @file_name = @study_file.upload_file_name
      @file_type = @study_file.file_type
      @missing_file_type = StudyFileBundle::CHILD_REQUIREMENTS[@file_type]
      DeleteQueueJob.new(@study_file).delay.perform
      render 'deleted_bundle'
    end
  end

  # method to download files if study is private, will create temporary signed_url after checking user quota
  def download_private_file
    @study = Study.find_by(accession: params[:accession])
    # verify user can download file
    verify_file_download_permissions(@study); return if performed?
    # initiate file download action
    execute_file_download(@study); return if performed?
  end

  # for files that don't need parsing, send directly to firecloud on upload completion
  def send_to_firecloud
    @study_file = StudyFile.find_by(study_id: params[:id], upload_file_name: params[:file])
    @study.delay.send_to_firecloud(@study_file)
    changes = ["Study file added: #{@study_file.upload_file_name}"]
    if @study.study_shares.any?
      SingleCellMailer.share_update_notification(@study, changes, current_user).deliver_now
    end
    head :ok
  end

  # update an existing study file via upload wizard; cannot be called until file is uploaded, so there is no create
  # if adding an external fastq file link, will create entry from scratch to update
  def update_study_file
    # rails renders out the array as a space delimited string in a hidden field, but doesn't
    # expect it back in the same format, so we have to parse the field for it
    cluster_id_array = params["study_file"]["spatial_cluster_associations"]
    if cluster_id_array.present? && cluster_id_array.count > 0
      params["study_file"]["spatial_cluster_associations"] = cluster_id_array[0].split(' ')
    end
    @study_file = StudyFile.find_by(study_id: study_file_params[:study_id], _id: study_file_params[:_id])
    @selector = params[:selector]
    @partial = params[:partial]
    if @study_file.nil?
      if study_file_params[:file_type] === 'Fastq' && study_file_params[:human_data].to_s === 'true'
        # only build new study file if this is an external human fastq
        @study_file = @study.study_files.build
      else
        logger.error "#{Time.zone.now}: Aborting study file save for file id #{study_file_params[:_id]} - file not found"
        # we get here if a user uploads a file, the parse fails, and they click 'Save' before refreshing the page
        @alert = "The study file in question has already been deleted (likely due to a parse failure).  The page will be refreshed to reflect the current status - please upload the file again before continuing."
        render js: "window.location.reload(); alert('#{@alert}');" and return
      end
    end

    # invalidate caches (even if transaction rolls back, the user wants to update so clearing is safe)
    if ['Cluster', 'Coordinate Labels', 'Gene List'].include?(@study_file.file_type) && @study_file.valid?
      @study_file.invalidate_cache_by_file_type
    end

    set_expression_form_state

    if @study_file.update(study_file_params)
      # if a gene list or cluster got updated, we need to update the associated records
      if study_file_params[:file_type] == 'Gene List'
        @precomputed_entry = PrecomputedScore.find_by(study_file_id: study_file_params[:_id])
        @precomputed_entry.update(name: @study_file.name)
      elsif study_file_params[:file_type] == 'Cluster'
        @cluster = ClusterGroup.find_by(study_file_id: study_file_params[:_id])
        # before updating, check if the defaults also need to change
        if @study.default_cluster == @cluster
          @study.default_options[:cluster] = @study_file.name
          @study.save
        end
        old_name = @cluster.name.dup
        @cluster.update(name: @study_file.name)
      elsif ['Expression Matrix', 'MM Coordinate Matrix'].include?(study_file_params[:file_type]) && !study_file_params[:y_axis_label].blank?
        # if user is supplying an expression axis label, update default options hash
        @study.update(default_options: @study.default_options.merge(expression_label: study_file_params[:y_axis_label]))
        @study.expression_matrix_files.first.invalidate_cache_by_file_type
      end
      @message = "'#{@study_file.name}' has been successfully updated."

      # notify users of updated file
      changes = ["Study file updated: #{@study_file.upload_file_name}"]
      if @study.study_shares.any?
        SingleCellMailer.share_update_notification(@study, changes, current_user).deliver_now
      end
    else
      respond_to do |format|
        format.js {render action: 'update_fail'}
      end
    end
  end

  # update an existing study file via sync page
  def update_study_file_from_sync
    @study_file = StudyFile.find_by(study_id: study_file_params[:study_id], _id: study_file_params[:_id])
    if @study_file.nil?
      # don't use helper as we're about to mass-assign params
      @study_file = @study.study_files.build
    end
    @form = "#study-file-#{@study_file.id}"

    # check if the name of the file has changed as we won't be able to tell after we saved
    name_changed = @study_file.name != study_file_params[:name]

    # do a test assignment and check for validity; if valid and either Cluster or Gene List, invalidate caches
    @study_file.assign_attributes(study_file_params)
    if ['Cluster', 'Coordinate Labels', 'Gene List'].include?(@study_file.file_type) && @study_file.valid?
      @study_file.delay.invalidate_cache_by_file_type # run this in the background reduce UI blocking
    end

    if @study_file.save
      # invalidate caches first
      @study_file.delay.invalidate_cache_by_file_type
      # if a gene list or cluster got updated, we need to update the associated records
      if study_file_params[:file_type] == 'Gene List' && name_changed
        @precomputed_entry = PrecomputedScore.find_by(study_file_id: study_file_params[:_id])
        logger.info "Updating gene list #{@precomputed_entry.name} to match #{study_file_params[:name]}"
        @precomputed_entry.update(name: @study_file.name)
      elsif study_file_params[:file_type] == 'Cluster' && name_changed
        @cluster = ClusterGroup.find_by(study_file_id: study_file_params[:_id])
        logger.info "Updating cluster #{@cluster.name} to match #{study_file_params[:name]}"

        # before updating, check if the defaults also need to change
        if @study.default_cluster == @cluster
          @study.default_options[:cluster] = @study_file.name
          @study.save
        end
        @cluster.update(name: @study_file.name)
      elsif study_file_params[:file_type] == 'Expression Matrix' && !study_file_params[:y_axis_label].blank?
        # if user is supplying an expression axis label, update default options hash
        @study.update(default_options: @study.default_options.merge(expression_label: study_file_params[:y_axis_label]))
      end
      @message = "'#{@study_file.name}' has been successfully updated."

      # only reparse if user requests
      if @study_file.parseable? && params[:reparse] == 'Yes'
        FileParseService.run_parse_job(@study_file, @study, current_user, reparse: true, persist_on_fail: true)
      end

      # notify users of updated file
      changes = ["Study file updated: #{@study_file.upload_file_name}"]
      if @study.study_shares.any?
        SingleCellMailer.share_update_notification(@study, changes, current_user).deliver_now
      end
    else
      @partial = 'synced_study_file_form'
      respond_to do |format|
        format.js {render action: 'update_fail'}
      end
    end
  end

  # delete the requested study file
  def delete_study_file
    @study_file = StudyFile.find(params[:study_file_id])
    @message = ""
    if @study_file.present?
      if !@study_file.can_delete_safely?
        render action: 'abort_delete_study_file'
      else
        human_data = @study_file.human_data # store this reference for later
        # delete matching caches
        @study_file.invalidate_cache_by_file_type
        # queue for deletion
        @file_type = @study_file.file_type
        @study_file.update(queued_for_deletion: true)
        DeleteQueueJob.new(@study_file).delay.perform
        @message = "'#{@study_file.name}' has been successfully deleted."
        @partial = @study_file.wizard_partial_name
        # delete source file in FireCloud and then remove record
        begin
          # make sure file is in FireCloud first as user may be aborting the upload
          unless human_data
            present = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, @study.bucket_id,
                                                                   @study_file.upload_file_name)
            if present
              ApplicationController.firecloud_client.execute_gcloud_method(:delete_workspace_file, 0, @study.bucket_id,
                                                           @study_file.upload_file_name)
            end
          end
        rescue => e
          ErrorTracker.report_exception(e, current_user, @study, params)
          MetricsService.report_error(e, request, current_user, @study)
          logger.error "Error in deleting #{@study_file.upload_file_name} from workspace: #{@study.firecloud_workspace}; #{e.message}"
          redirect_to merge_default_redirect_params(request.referrer, scpbr: params[:scpbr]),
                      alert: "We were unable to delete #{@study_file.upload_file_name} due to an error: " \
                             "#{view_context.simple_format(e.message)}.  Please try again later.  #{SCP_SUPPORT_EMAIL}"
        end
        changes = ["Study file deleted: #{@study_file.upload_file_name}"]
        if @study.study_shares.any?
          SingleCellMailer.share_update_notification(@study, changes, current_user).deliver_now
        end
      end
    else
      # user most likely aborted upload before it began, so determine file type based on form target
      @message = "Upload sucessfully cancelled."
      case params[:target]
      when /expression/
        @file_type = 'Expression Matrix'
        @partial = 'initialize_expression_form'
      when /metadata/
        @file_type = 'Metadata'
        @partial = 'initialize_metadata_form'
      when /ordinations/
        @file_type = 'Cluster'
        @partial = 'initialize_ordinations_form'
      when /labels/
        @file_type = 'Coordinate Labels'
        @partial = 'initialize_labels_form'
      when /marker/
        @file_type = 'Gene List'
        @partial = 'initialize_marker_genes_form'
      when /primary/
        @file_type = 'Fastq'
        @partial = 'initialize_primary_data_form'
      else
        @file_type = 'Other'
        @partial = 'initialize_misc_form'
      end
    end

    # determine state for processed matrix overlay
    set_expression_form_state

    is_required = ['Cluster', 'Expression Matrix', 'Metadata'].include?(@file_type)
    @color = is_required ? 'danger' : 'info'
    @status = is_required ? 'Required' : 'Optional'
    @study_file = @study.build_study_file({file_type: @file_type})
    @allow_only = params[:allow_only] || 'all'
    if @file_type =~ /Matrix/
      @study_file.build_expression_file_info(is_raw_counts: @allow_only == 'raw')
    end

    # logic for rolling back status bar in upload wizard; need to account for raw vs. processed matrix files
    if @file_type.present? && @file_type =~ /Matrix/
      is_raw_counts = @study_file.is_raw_counts_file?
      @reset_status = @study.study_files.valid.select do |sf|
        sf.file_type =~ /Matrix/ && !sf.new_record? && (is_raw_counts ? sf.is_raw_counts_file? : !sf.is_raw_counts_file?)
      end.count == 0
    elsif @file_type.present?
      @reset_status = @study.study_files.valid.select { |sf| sf.file_type == @file_type && !sf.new_record? }.count == 0
    else
      @reset_status = false
    end
  end

  def generate_manifest
    manifest_obj = BulkDownloadService.generate_study_files_tsv(@study)
    render plain: manifest_obj
  end

  def usage_stats
  end

  # adding new study_file entries based on remote files in GCP
  def sync_study_file
    @study_file = @study.study_files.build
    @partial = 'study_file_form'
    if @study_file.update(study_file_params)
      # fix content headers
      StudySyncService.fix_file_content_headers(@study_file)
      if study_file_params[:file_type] == 'Expression Matrix' && !study_file_params[:y_axis_label].blank?
        # if user is supplying an expression axis label, update default options hash
        @study.update(default_options: @study.default_options.merge(expression_label: study_file_params[:y_axis_label]))
        @study.expression_matrix_files.first.invalidate_cache_by_file_type
      else
        # invalidate caches
        @study_file.delay.invalidate_cache_by_file_type
      end

      @message = "New Study File '#{@study_file.name}' successfully synced."
      # only grab id after update as it will change on new entries
      @form = "#study-file-#{@study_file.id}"
      @target = "#synced-study-files"

      if @study_file.parseable?
        FileParseService.run_parse_job(@study_file, @study, current_user, reparse: false, persist_on_fail: true)
      elsif @study_file.file_type == 'BAM'
        # we need to check if we have a study_file_bundle here
        @study_file_bundle = StudyFileBundle.initialize_from_parent(@study, @study_file)
        index_file = @study.study_files.find_by('options.bam_id' => @study_file.id.to_s)
        if index_file.present?
          @study_file_bundle.add_files(index_file)
        end
      elsif @study_file.file_type == 'BAM Index'
        # add this index to the study_file_bundle, which should already be present
        bam_file = @study.study_files.find_by(id: @study_file.options[:bam_id])
        @study_file_bundle = StudyFileBundle.initialize_from_parent(@study, bam_file)
        if @study_file_bundle.bundled_files.detect {|f| f.upload_file_name == @study_file.upload_file_name}.nil?
          @study_file_bundle.add_files(@study_file)
        end
        @target = "#study-file-#{@study_file.options[:bam_id]}"
      end
      respond_to do |format|
        format.js
      end
    else
      @form = "#study-file-#{@study_file.id}"
      respond_to do |format|
        format.js {render action: 'sync_action_fail'}
      end
    end
  end

  # re-associated a study_file entry in the database with a remote file in GCP that has changed
  def sync_orphaned_study_file
    @study_file = StudyFile.find_by(study_id: study_file_params[:study_id], _id: study_file_params[:_id])
    @form = "#study-file-#{@study_file.id}"
    @partial = 'orphaned_study_file_form'
    # overwrite name with requested file unless study_file is a cluster or gene list
    update_params = study_file_params
    if @study_file.file_type != 'Cluster' && @study_file.file_type != 'Gene List'
      update_params[:name] = params[:existing_file]
    end

    if @study_file.update(update_params)
      if update_params[:file_type] == 'Expression Matrix' && !update_params[:y_axis_label].blank?
        # if user is supplying an expression axis label, update default options hash
        @study.update(default_options: @study.default_options.merge(expression_label: update_params[:y_axis_label]))
        @study.expression_matrix_files.first.invalidate_cache_by_file_type
      end
      @message = "New Study File '#{@study_file.name}' successfully synced."
      # only reparse if user requests
      if @study_file.parseable? && params[:reparse] == 'Yes'
        FileParseService.run_parse_job(@study_file, @study, current_user, reparse: true, persist_on_fail: true)
      elsif @study_file.file_type == 'BAM'
        # we need to check if we have a study_file_bundle here
        @study_file_bundle = StudyFileBundle.initialize_from_parent(@study, @study_file)
        index_file = @study.study_files.find_by('options.bam_id' => @study_file.id.to_s)
        if index_file.present?
          @study_file_bundle.add_files(index_file)
        end
      elsif @study_file.file_type == 'BAM Index'
        # add this index to the study_file_bundle, which should already be present
        bam_file = @study.study_files.find_by(id: @study_file.options[:bam_id])
        @study_file_bundle = StudyFileBundle.initialize_from_parent(@study, bam_file)
        if @study_file_bundle.bundled_files.detect {|f| f.upload_file_name == @study_file.upload_file_name}.nil?
          @study_file_bundle.add_files(@study_file)
        end
      end

      respond_to do |format|
        format.js {render action: 'sync_study_file'}
      end
    else
      respond_to do |format|
        format.js {render action: 'sync_action_fail'}
      end
    end
  end

  # similar to delete_study_file, but called when a study_file record has been orphaned (no corresponding bucket file)
  def unsync_study_file
    @study_file = StudyFile.find(params[:study_file_id])
    @form = "#study-file-#{@study_file.id}"
    @message = ""
    unless @study_file.nil?
      if !@study_file.can_delete_safely?
        render action: 'abort_delete_study_file'
      else
        begin
          DeleteQueueJob.new(@study_file).delay.perform

          changes = ["Study file deleted: #{@study_file.upload_file_name}"]
          if @study.study_shares.any?
            SingleCellMailer.share_update_notification(@study, changes, current_user).deliver_now
          end

          # delete matching caches
          @study_file.delay.invalidate_cache_by_file_type
          @message = "'#{@study_file.name}' has been successfully deleted."

          # reset initialized if needed
          if @study.cluster_ordinations_files.empty? || @study.expression_matrix_files.nil? || @study.metadata_file.nil?
            @study.update(initialized: false)
          end

          respond_to do |format|
            format.js {render action: 'sync_action_success'}
          end
        rescue => e
          ErrorTracker.report_exception(e, current_user, @study, params)
          MetricsService.report_error(e, request, current_user, @study)
          respond_to do |format|
            format.js {render action: 'sync_action_fail'}
          end
        end
      end
    end
  end

  ###
  #
  # DIRECTORYLISTING OBJECT METHODS
  #
  ###

  # synchronize a directory_listing object
  def sync_directory_listing
    @directory = DirectoryListing.find(directory_listing_params[:_id])
    @form = "#directory-listing-#{@directory.id}"
    if @directory.update(directory_listing_params)
      @message = "Directory listing for '#{@directory.name}' successfully synced."
      respond_to do |format|
        format.js {render action: 'sync_directory_listing'}
      end
    else
      respond_to do |format|
        format.js {render action: 'sync_action_fail'}
      end
    end
  end

  # delete a directory_listing object
  def delete_directory_listing
    @directory = DirectoryListing.find(params[:directory_listing_id])
    @form = "#directory-listing-#{@directory.id}"
    if @directory.destroy
      @message = "Directory listing for '#{@directory.name}' successfully unsynced."
      respond_to do |format|
        format.js {render action: 'sync_action_success'}
      end
    else
      respond_to do |format|
        format.js {render action: 'sync_action_fail'}
      end
    end
  end

  ###
  #
  # STUDY DEFAULT OPTIONS METHODS
  #
  ###

  # update the default_options field for a study
  def update_default_options
    @study.default_options = default_options_params.to_h
    # get new annotation type from parameters
    new_annotation_type = default_options_params[:annotation].split('--')[1]
    # clean up color profile if changing from numeric- to group-based annotation
    if new_annotation_type == 'group'
      @study.default_options[:color_profile] = nil
    end
    if @study.save
      # invalidate all cluster & expression caches as points sizes/borders may have changed globally
      # start with default cluster then do everything else
      @study.default_cluster.study_file.invalidate_cache_by_file_type
      other_clusters = @study.cluster_groups.keep_if {|cluster_group| cluster_group.name != @study.default_cluster}
      other_clusters.map {|cluster_group| cluster_group.study_file.invalidate_cache_by_file_type}
      @study.expression_matrix_files.map {|matrix_file| matrix_file.invalidate_cache_by_file_type}
      set_study_default_options
      render action: 'update_default_options_success'
    else
      set_study_default_options
      render action: 'update_default_options_fail'
    end
  end

  # load annotations for a given study and cluster
  def load_annotation_options
    @default_cluster = @study.cluster_groups.detect {|cluster| cluster.name == params[:cluster]}
    @default_cluster_annotations = {
        'Study Wide' => @study.cell_metadata.map {|metadata| ["#{metadata.name}", "#{metadata.name}--#{metadata.annotation_type}--study"] }.uniq
    }
    unless @default_cluster.nil?
      @default_cluster_annotations['Cluster-based'] = @default_cluster.cell_annotations.map {|annot| ["#{annot[:name]}", "#{annot[:name]}--#{annot[:type]}--cluster"]}
    end
  end

  private

  ###
  #
  # SETTERS
  #
  ###

  def set_study
    @study = Study.find(params[:id])
  end

  # study params list
  def study_params
    params.require(:study).permit(:name, :description, :public, :user_id, :embargo, :use_existing_workspace, :firecloud_workspace,
                                  :firecloud_project, branding_group_ids: [],
                                  study_shares_attributes: [:id, :_destroy, :email, :permission],
                                  external_resources_attributes: [:id, :_destroy, :title, :description, :url, :publication_url],
                                  study_detail_attributes: [:id, :full_description])
  end

  # study file params list
  def study_file_params
    params.require(:study_file).permit(:_id, :study_id, :name, :upload, :upload_file_name, :upload_content_type, :upload_file_size,
                                       :remote_location, :description, :file_type, :status, :human_fastq_url, :human_data, :use_metadata_convention,
                                       :cluster_type, :generation, :x_axis_label, :y_axis_label, :z_axis_label, :x_axis_min, :x_axis_max,
                                       :y_axis_min, :y_axis_max, :z_axis_min, :z_axis_max, :is_spatial, :taxon_id, :genome_assembly_id, :study_file_bundle_id,
                                       :external_link_url, :external_link_title, :external_link_description,
                                       spatial_cluster_associations: [],
                                       options: [:cluster_group_id, :cluster_file_id, :font_family, :font_size, :font_color,
                                                 :matrix_id, :submission_id, :bam_id, :analysis_name, :visualization_name,
                                                 :cluster_name, :annotation_name],
                                       expression_file_info_attributes: [:id, :library_preparation_protocol, :units,
                                                                         :biosample_input_type, :modality, :is_raw_counts,
                                                                         raw_counts_associations: []])
  end

  def directory_listing_params
    params.require(:directory_listing).permit(:_id, :study_id, :name, :description, :sync_status, :file_type, :taxon_id, :genome_assembly_id)
  end

  def default_options_params
    params.require(:study_default_options).permit(:cluster, :annotation, :color_profile, :expression_label,
                                                  :cluster_point_size, :cluster_point_alpha, :cluster_point_border,
                                                  :precomputed_heatmap_label, override_viz_limit_annotations: [])
  end

  def set_file_types
    @file_types = StudyFile::STUDY_FILE_TYPES
  end

  # return upload object from study params
  def get_upload
    study_file_params.to_h['upload']
  end

  # set up variables for wizard
  def initialize_wizard_files
    @all_expression = @study.study_files.by_type(['Expression Matrix', 'MM Coordinate Matrix'])
    # divide all expression files into raw/processed bins
    @raw_matrix_files, @processed_matrix_files = @all_expression.partition(&:is_raw_counts_file?)
    @block_processed_upload = @raw_matrix_files.empty? &&
                              !FeatureFlaggable.flag_override_for_instances('raw_counts_required_frontend', false,
                                                                            current_user, @study)
    @metadata_file = @study.metadata_file
    @cluster_ordinations = @study.study_files.by_type('Cluster')
    @coordinate_labels = @study.study_files.by_type('Coordinate Labels')
    @marker_lists = @study.study_files.by_type('Gene List')
    @fastq_files = @study.study_files.by_type(['Fastq', 'BAM'])
    @other_files = @study.study_files.by_type(['Documentation', 'Other'])

    # if files don't exist, build them for use later (excluding coordinate labels as we need the data to be current)
    if @raw_matrix_files.empty?
      matrix = @study.build_study_file({ file_type: 'Expression Matrix', expression_file_info: { is_raw_counts: true } })
      @raw_matrix_files << matrix
    end
    if @processed_matrix_files.empty?
      matrix = @study.build_study_file({ file_type: 'Expression Matrix', expression_file_info: { is_raw_counts: false } })
      @processed_matrix_files << matrix
    end
    if @metadata_file.nil?
      @metadata_file = @study.build_study_file({ file_type: 'Metadata' })
    end
    if @cluster_ordinations.empty?
      @cluster_ordinations << @study.build_study_file({ file_type: 'Cluster' })
    end
    if @marker_lists.empty?
      @marker_lists << @study.build_study_file({ file_type: 'Gene List' })
    end
    if @fastq_files.empty?
      @fastq_files << @study.build_study_file({ file_type: 'Fastq' })
    end
    if @other_files.empty?
      @other_files << @study.build_study_file({ file_type: 'Documentation' })
    end
    (@raw_matrix_files + @processed_matrix_files).each do |file|
      file.build_expression_file_info if file.expression_file_info.nil?
    end
  end

  def set_expression_form_state
    # if feature flag is enabled, ensure there are raw count matrix files
    if @study.study_files.where(file_type: /Matrix/, queued_for_deletion: false,
                                'expression_file_info.is_raw_counts' => true).empty? &&
      !FeatureFlaggable.flag_override_for_instances('raw_counts_required_frontend', false, current_user, @study)
      @block_processed_upload = true
    else
      @block_processed_upload = false
    end
    @allow_only = params[:allow_only] || 'all'
  end

  def set_user_projects
    @projects = [['Default Project', FireCloudClient::PORTAL_NAMESPACE]]
    begin
      client = FireCloudClient.new(current_user, 'single-cell-portal')
      if current_user.registered_for_firecloud && client.registered?
        available_projects = client.get_billing_projects
        available_projects.each do |project|
          if project['creationStatus'] == 'Ready'
            @projects << [project['projectName'], project['projectName']]
          end
        end
      end
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      MetricsService.report_error(e, request, current_user, @study)
      Rails.logger.error "Error setting user projects for #{current_user.email}: #{e.message}"
    end
  end

  ###
  #
  # PERMISSONS & STATUS CHECKS
  #
  ###

  def check_edit_permissions
    if !user_signed_in? || !@study.can_edit?(current_user)
      alert = "You do not have permission to perform that action.  #{SCP_SUPPORT_EMAIL}"
      respond_to do |format|
        format.js {render js: "alert('#{alert}')" and return}
        format.html {redirect_to merge_default_redirect_params(studies_path, scpbr: params[:scpbr]),
                                 alert: alert and return}
      end
    end
  end

  # check on FireCloud API status and respond accordingly
  def check_firecloud_status
    unless ApplicationController.firecloud_client.services_available?(FireCloudClient::SAM_SERVICE, FireCloudClient::RAWLS_SERVICE)
      alert = "Study workspaces are temporarily unavailable, so we cannot complete your request.  Please try again later.  #{SCP_SUPPORT_EMAIL}"
      respond_to do |format|
        format.js {render js: "$('.modal').modal('hide'); alert('#{alert}')" and return}
        format.html {redirect_to merge_default_redirect_params(studies_path, scpbr: params[:scpbr]),
                                 alert: alert and return}
        format.json {head 503}
      end
    end
  end

  # check if a study is 'detached' and handle accordingly
  def check_study_detached
    if @study.detached
      redirect_to merge_default_redirect_params(request.referrer, scpbr: params[:scpbr]),
                  alert: "We were unable to complete your request as the study is question is detached from the workspace " \
                         "(maybe the workspace was deleted?).  #{SCP_SUPPORT_EMAIL}" and return

    end
  end

  ###
  #
  # SYNC SUB METHODS
  #
  ###

  def process_workflow_output(output_name, file_url, remote_gs_file, workflow, submission_id, submission_config)
    path_parts = file_url.split('/')
    basename = path_parts.last
    new_location = "outputs_#{@study.id}_#{submission_id}/#{basename}"
    # check if file has already been synced first
    # we can only do this by md5 hash as the filename and generation will be different
    existing_file = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, @study.bucket_id, new_location)
    unless existing_file.present? && existing_file.md5 == remote_gs_file.md5 && StudyFile.where(study_id: @study.id, upload_file_name: new_location).exists?
      # now copy the file to a new location for syncing, marking as default type of 'Analysis Output'
      new_file = remote_gs_file.copy new_location
      unsynced_output = StudyFile.new(study_id: @study.id, name: new_file.name, upload_file_name: new_file.name,
                                      upload_content_type: new_file.content_type, upload_file_size: new_file.size,
                                      generation: new_file.generation, remote_location: new_file.name,
                                      options: {submission_id: params[:submission_id]})
      unsynced_output.build_expression_file_info
      # process output according to analysis_configuration output parameters and associations (if present)
      workflow_parts = output_name.split('.')
      call_name = workflow_parts.shift
      param_name = workflow_parts.join('.')
      if @special_sync # only process outputs from 'registered' analyses
        Rails.logger.info "Processing output #{output_name}:#{file_url} in #{params[:submission_id]}/#{workflow['workflowId']}"
        # find matching output analysis_parameter
        output_param = @analysis_configuration.analysis_parameters.outputs.detect {|param| param.parameter_name == param_name && param.call_name == call_name}
        # set declared file type
        unsynced_output.file_type = output_param.output_file_type
        # process any direct attribute assignments or associations
        output_param.analysis_output_associations.each do |association|
          unsynced_output = association.process_output_file(unsynced_output, submission_config, @study)
        end
      end
      @unsynced_files << unsynced_output
    end
  end

  # match filenames that start with a . or have a /. in their path
  HIDDEN_FILE_REGEX = /\/\.|^\./
  def visible_unsynced_files
    @unsynced_files.select { |f| HIDDEN_FILE_REGEX.match(f.upload_file_name).nil? }
  end

  def hidden_unsynced_files
    @unsynced_files.select { |f| HIDDEN_FILE_REGEX.match(f.upload_file_name).present? }
  end

end
