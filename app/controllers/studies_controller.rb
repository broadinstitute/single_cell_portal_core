class StudiesController < ApplicationController
  before_action :set_study, only: [:show, :edit, :update, :initialize_study, :destroy, :upload, :do_upload, :resume_upload, :update_status, :reset_upload, :new_study_file, :update_study_file, :delete_study_file, :retrieve_upload, :retrieve_wizard_upload, :parse, :launch_parse_job, :parse_progress]
  before_filter :check_edit_permissions, except: [:index, :new, :create, :download_private_file]
  before_filter :authenticate_user!

  # GET /studies
  # GET /studies.json
  def index
    @studies = Study.editable(current_user).to_a
  end

  # GET /studies/1
  # GET /studies/1.json
  def show
  end

  # GET /studies/new
  def new
    @study = Study.new
  end

  # GET /studies/1/edit
  def edit
  end

  # POST /studies
  # POST /studies.json
  def create
    @study = Study.new(study_params)

    respond_to do |format|
      if @study.save
        format.html { redirect_to initialize_study_path(@study), notice: "Your study '#{@study.name}' was successfully created." }
        format.json { render :show, status: :ok, location: @study }
      else
        format.html { render :new }
        format.json { render json: @study.errors, status: :unprocessable_entity }
      end
    end
  end

  # wizard for adding study files after user creates a study
  def initialize_study
    # load any existing files if user restarted for some reason (unlikely)
    intitialize_wizard_files
    # check if study has been properly initialized yet, set to true if not
    if !@cluster_ordinations.last.new_record? && !@expression_file.new_record? && !@metadata_file.new_record? && !@study.initialized?
      @study.update_attributes(initialized: true)
    end
  end

  # PATCH/PUT /studies/1
  # PATCH/PUT /studies/1.json
  def update
    respond_to do |format|
      if @study.update(study_params)
        format.html { redirect_to studies_path, notice: "Study '#{@study.name}' was successfully updated." }
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
    name = @study.name
    ### GOTCHA ON MEMORY USAGE
    # calling @study.destroy will load all dependent objects into memory and call their dependent removal methods
    # even if the association is dependent: :delete, it still has to be loaded into memory and removed one at a time
    # instead, manually remove any documents with Model.delete_all that will consume a lot of RAM (expression_scores,
    # study_metadatas, data_arrays and precomputed_scores) before calling @study.destroy to remove all other objects
    ExpressionScore.where(study_id: @study.id).delete_all
    DataArray.where(study_id: @study.id).delete_all
    StudyMetadata.where(study_id: @study.id).delete_all
    PrecomputedScore.where(study_id: @study.id).delete_all

    # now we can delete the study to remove study_files, cluster_groups and any other children
    @study.destroy
    respond_to do |format|
      format.html { redirect_to studies_path, notice: "Study '#{name}'was successfully destroyed.  All uploaded data & parsed database records have also been destroyed." }
      format.json { head :no_content }
    end
  end

  # parses file in foreground to maintain UI state for immediate messaging
  def parse
    @study_file = StudyFile.where(study_id: params[:id], upload_file_name: params[:file]).first
    logger.info "Parsing #{@study_file.name} as #{@study_file.file_type} in study #{@study.name}"
    case @study_file.file_type
      when 'Cluster'
        @study.delay.initialize_cluster_group_and_data_arrays(@study_file, current_user)
      when 'Expression Matrix'
        @study.delay.make_expression_scores(@study_file, current_user)
      when 'Gene List'
        @study.delay.make_precomputed_scores(@study_file, current_user)
      when 'Metadata'
        @study.delay.initialize_study_metadata(@study_file, current_user)
    end
  end

  def parse_progress
    @study_file = StudyFile.where(study_id: params[:id], upload_file_name: params[:file]).first
    # gotcha in case parsing has failed and study file as been destroyed
    if @study_file.nil?
      render nothing: true
    end
  end

  # create a new study_file for requested study
  def new_study_file
    file_type = params[:file_type] ? params[:file_type] : 'Cluster'
    cluster_type = params[:cluster_type] ? params[:cluster_type] : nil
    @study_file = @study.build_study_file({file_type: file_type, cluster_type: cluster_type})
  end

  # update an existing study file; cannot be called until file is uploaded, so there is no create
  # if adding an external fastq file link, will create entry from scratch to update
  def update_study_file
    @study_file = StudyFile.where(study_id: study_file_params[:study_id], _id: study_file_params[:_id]).first
    if @study_file.nil?
      # don't use helper as we're about to mass-assign params
      @study_file = @study.study_files.build
    end
    @study_file.update_attributes(study_file_params)
    # if a gene list got updated, we need to update the precomputed_score entry
    if study_file_params[:file_type] == 'Gene List'
      @precomputed_entry = PrecomputedScore.where(study_file_id: study_file_params[:_id])
      @precomputed_entry.update(name: study_file_params[:name])
    end
    @message = "'#{@study_file.name}' has been successfully updated."
    @selector = params[:selector]
    @partial = params[:partial]
  end

  # delete the requested study file
  def delete_study_file
    @study_file = StudyFile.find(params[:study_file_id])
    @message = ""
    unless @study_file.nil?
      @file_type = @study_file.file_type
      @message = "'#{@study_file.name}' has been successfully deleted."
      # clean up records before removing file (for memory optimization)
      case @file_type
        when 'Cluster'
          ClusterGroup.where(study_file_id: @study_file.id, study_id: @study.id).delete_all
          DataArray.where(study_file_id: @study_file.id, study_id: @study.id).delete_all
          @partial = 'initialize_ordinations_form'
        when 'Expression Matrix'
          ExpressionScore.where(study_file_id: @study_file.id, study_id: @study.id).delete_all
          DataArray.where(study_file_id: @study_file.id, study_id: @study.id).delete_all
          @partial = 'initialize_expression_form'
        when 'Metadata'
          StudyMetadata.where(study_file_id: @study_file.id, study_id: @study.id).delete_all
          @partial = 'initialize_metadata_form'
        when 'Fastq'
          @partial = 'initialize_fastq_form'
        when 'Gene List'
          PrecomputedScore.where(study_file_id: @study_file.id, study_id: @study.id).delete_all
          @partial = 'initialize_marker_genes_form'
        else
          @partial = 'initialize_misc_form'
      end
      # remove record to also delete uploaded source file
      @study_file.destroy
      if @study.cluster_ordinations_files.empty? || @study.expression_matrix_file.nil? || @study.metadata_file.nil?
        @study.update(initialized: false)
      end
    end
    is_required = ['Cluster', 'Expression Matrix', 'Metadata'].include?(@file_type)
    @color = is_required ? 'danger' : 'info'
    @status = is_required ? 'Required' : 'Optional'
    @study_file = @study.build_study_file({file_type: @file_type})

    unless @file_type.nil?
      @reset_status = @study.study_files.select {|sf| sf.file_type == @file_type && !sf.new_record?}.count == 0
    else
      @reset_status = false
    end
  end

  # method to perform chunked uploading of data
  def do_upload
    upload = get_upload
    filename = upload.original_filename
    study_file = @study.study_files.select {|sf| sf.upload_file_name == filename}.first
    # If no file has been uploaded or the uploaded file has a different filename,
    # do a new upload from scratch
    if study_file.nil?
      # don't use helper as we're about to mass-assign params
      study_file = @study.study_files.build
      study_file.update(study_file_params)
      render json: { file: { name: study_file.errors,size: nil } } and return
      # If the already uploaded file has the same filename, try to resume
    else
      current_size = study_file.upload_file_size
      content_range = request.headers['CONTENT-RANGE']
      begin_of_chunk = content_range[/\ (.*?)-/,1].to_i # "bytes 100-999999/1973660678" will return '100'

      # If the there is a mismatch between the size of the incomplete upload and the content-range in the
      # headers, then it's the wrong chunk!
      # In this case, start the upload from scratch
      unless begin_of_chunk == current_size
        render json: study_file.to_jq_upload and return
      end
      # Add the following chunk to the incomplete upload, converting to unix line endings
      File.open(study_file.upload.path, "ab") { |f| f.write(upload.read.gsub(/\r\n?/, "\n")) }

      # Update the upload_file_size attribute
      study_file.upload_file_size = study_file.upload_file_size.nil? ? upload.size : study_file.upload_file_size + upload.size
      study_file.save!

      render json: study_file.to_jq_upload and return
    end
  end

  # GET /courses/:id/reset_upload
  def reset_upload
    # Allow users to delete uploads only if they are incomplete
    study_file = StudyFile.where(study_id: params[:id], name: params[:file]).first
    raise StandardError, "Action not allowed" unless study_file.status == 'uploading'
    study_file.update!(status: 'new', upload: nil)
    redirect_to upload_study_path(@study._id), notice: "Upload reset successfully. You can now start over"
  end

  # GET /courses/:id/resume_upload.json
  def resume_upload
    study_file = StudyFile.where(study_id: params[:id], name: params[:file]).first
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
    study_file = StudyFile.where(study_id: params[:id], upload_file_name: params[:file]).first
    study_file.update!(status: params[:status])
    head :ok
  end

  # retrieve study file by filename
  def retrieve_upload
    @study_file = StudyFile.where(study_id: params[:id], upload_file_name: params[:file]).first
  end

  # retrieve study file by filename during initializer wizard
  def retrieve_wizard_upload
    @study_file = StudyFile.where(study_id: params[:id], upload_file_name: params[:file]).first
  end

  # method to download files if study is private, will create temporary symlink and remove after timeout
  def download_private_file
    @study = Study.find_by(url_safe_name: params[:study_name])
    # check if user has permission in case someone is phishing
    if current_user.nil? || !@study.can_view?(current_user)
      redirect_to site_path, alert: 'You do not have permission to perform that action' and return
    else
      @study_file = @study.study_files.select {|sf| sf.upload_file_name == params[:filename]}.first
      @templink = TempFileDownload.create!({study_file_id: @study_file._id})
      @valid_until = @templink.created_at + TempFileDownloadCleanup::DEFAULT_THRESHOLD.minutes
      # redirect directly to file to trigger download
      redirect_to @templink.download_url
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_study
    @study = Study.find(params[:id])
  end

  # study params whitelist
  def study_params
    params.require(:study).permit(:name, :description, :public, :user_id, :embargo, study_files_attributes: [:id, :_destroy, :name, :path, :upload, :description, :file_type, :status], study_shares_attributes: [:id, :_destroy, :email, :permission])
  end

  # study file params whitelist
  def study_file_params
    params.require(:study_file).permit(:_id, :study_id, :name, :upload, :description, :file_type, :status, :human_fastq_url, :human_data, :cluster_type, :x_axis_label, :y_axis_label, :z_axis_label)
  end

  def clusters_params
    params.require(:clusters).permit(:assignment_file, :cluster_file, :cluster_type)
  end

  def expression_params
    params.require(:expression).permit(:expression_file)
  end

  def precomputed_params
    params.require(:precomputed).permit(:precomputed_file, :precomputed_name)
  end

  # return upload object from study params
  def get_upload
    study_file_params.to_h['upload']
  end

  def check_edit_permissions
    if !@study.can_edit?(current_user)
      redirect_to studies_path, alert: 'You do not have permission to perform that action' and return
    end
  end

  # set up variables for wizard
  def intitialize_wizard_files
    @expression_file = @study.expression_matrix_file
    @metadata_file = @study.metadata_file
    @cluster_ordinations = @study.study_files.select {|sf| sf.file_type == 'Cluster'}
    @sub_clusters = @study.study_files.select {|sf| sf.file_type == 'Cluster Coordinates' && sf.cluster_type == 'sub'}
    @marker_lists = @study.study_files.select {|sf| sf.file_type == 'Gene List'}
    @fastq_files = @study.study_files.select {|sf| sf.file_type == 'Fastq'}
    @other_files = @study.study_files.select {|sf| %w(Documentation Other).include?(sf.file_type)}

    # if files don't exist, build them for use later
    if @expression_file.nil?
      @expression_file = @study.build_study_file({file_type: 'Expression Matrix'})
    end
    if @metadata_file.nil?
      @metadata_file = @study.build_study_file({file_type: 'Metadata'})
    end
    if @cluster_ordinations.empty?
      @cluster_ordinations << @study.build_study_file({file_type: 'Cluster'})
    end
    if @marker_lists.empty?
      @marker_lists << @study.build_study_file({file_type: 'Gene List'})
    end
    if @fastq_files.empty?
      @fastq_files << @study.build_study_file({file_type: 'Fastq'})
    end
    if @other_files.empty?
      @other_files << @study.build_study_file({file_type: 'Documentation'})
    end
  end
end
