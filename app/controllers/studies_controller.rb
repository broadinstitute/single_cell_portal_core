class StudiesController < ApplicationController
  before_action :set_study, only: [:show, :edit, :update, :initialize_study, :destroy, :upload, :do_upload, :resume_upload, :update_status, :reset_upload, :new_study_file, :update_study_file, :delete_study_file, :retrieve_upload, :retrieve_wizard_upload, :parse, :launch_parse_job, :parse_progress]
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
    if !@assignment_file.new_record? && !@parent_cluster.new_record? && !@expression_file.new_record? && !@study.initialized?
      @study.update({initialized: true})
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
    begin
      case @study_file.file_type
        when 'Cluster Assignments'
          @study.make_clusters_and_cells(@study_file)
        when 'Cluster Coordinates'
          @study.make_cluster_points(@study.cluster_assignment_file, @study_file, @study_file.cluster_type)
        when 'Expression Matrix'
          @study.make_expression_scores(@study_file)
        when 'Gene List'
          @study.make_precomputed_scores(@study_file)
      end
    rescue StandardError => e
      logger.info "ERROR: #{e.message}"
      @error = e.message
      # remove bad study file, reload good entries
      @study_file.destroy
      intitialize_wizard_files
      case params[:partial]
        when 'initialize_assignments_form'
          @study_file = @assignment_file
        when 'initialize_clusters_form'
          @study_file = @parent_cluster
        when 'initialize_expression_form'
          @study_file = @expression_file
        when 'initialize_sub_clusters_form'
          @study_file = @study.build_study_file({file_type: 'Cluster Coordinates', cluster_type: 'sub'})
        when 'initialize_marker_genes_form'
          @study_file = @study.build_study_file({file_type: 'Gene List'})
        when 'initialize_fastq_form'
          @study_file = @study.build_study_file({file_type: 'Fastq'})
        when 'initialize_misc_form'
          @study_file = @study.build_study_file({file_type: 'Other'})
        else
          @study_file = @study.build_study_file({file_type: 'Other'})
      end
      render 'parse_error'
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
    file_type = params[:file_type] ? params[:file_type] : 'Cluster Assignments'
    cluster_type = params[:cluster_type] ? params[:cluster_type] : nil
    @study_file = @study.build_study_file({file_type: file_type, cluster_type: cluster_type})
  end

  # update an existing study file; cannot be called until file is uploaded, so there is no create
  # if adding an external fastq file link, will create entry from scratch to update
  def update_study_file
    @study_file = StudyFile.where(study_id: study_file_params[:study_id], upload_file_name: study_file_params[:name]).first
    if @study_file.nil?
      # don't use helper as we're about to mass-assign params
      @study_file = @study.study_files.build
    end
    @study_file.update_attributes(study_file_params)
    @message = "'#{@study_file.name}' has been successfully updated."
  end

  # delete the requested study file
  def delete_study_file
    @study_file = StudyFile.find(params[:study_file_id])
    @message = ""
    unless @study_file.nil?
      @file_type = @study_file.file_type
      @cluster_type = @study_file.cluster_type
      @message = "'#{@study_file.name}' has been successfully deleted."
      @study_file.destroy
      # gotcha in case user deletes assignments file, must remove all clusters too due to associations
      if @file_type == 'Cluster Assignments'
        StudyFile.destroy_all(study_id: @study._id, file_type: 'Cluster Coordinates')
        @message += "  Since you deleted the cluster assignments for your study, all coordinates files have also been deleted.<br/></br/><strong class='text-danger'>Please refresh your screen to update the status accordingly.</strong>"
      end
      if @study.cluster_assignment_file.nil? || @study.parent_cluster_coordinates_file.nil? || @study.expression_matrix_file.nil?
        @study.update(initialized: false)
      end
    end
    @color = 'danger'
    @status = 'Required'
    case params[:target]
      when '#assignments_form'
        @study_file = @study.build_study_file({file_type: 'Cluster Assignments'})
        @reset_status = true
        @partial = 'initialize_assignments_form'
      when '#parent_cluster_form'
        @study_file = @study.build_study_file({file_type: 'Cluster Coordinates', cluster_type: 'parent'})
        @reset_status = true
        @partial = 'initialize_clusters_form'
      when '#expression_form'
        @study_file = @study.build_study_file({file_type: 'Expression Matrix'})
        @reset_status = true
        @partial = 'initialize_expression_form'
      else
        @color = 'info'
        @status = 'Optional'
        @study_file = @study.build_study_file({file_type: @file_type, cluster_type: @cluster_type})
        parts = params[:target].gsub(/#/, '').split('_')
        parts.pop
        @partial = 'initialize_' + parts.join('_');
        unless @file_type.nil?
          @reset_status = @study.study_files.select {|sf| sf.file_type == @file_type && sf.cluster_type == @cluster_type && !sf.new_record?}.count == 0
        else
          @reset_status = false
        end
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

  # PATCH /courses/:id/update_upload_status
  def update_status
    study_file = StudyFile.where(study_id: params[:id], upload_file_name: params[:file]).first
    raise ArgumentError, "Wrong status provided " + params[:status] unless study_file.status == 'uploading' && params[:status] == 'uploaded'
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
    @study_file = @study.study_files.select {|sf| sf.upload_file_name == params[:filename]}.first
    @templink = TempFileDownload.create!({study_file_id: @study_file._id})
    @valid_until = @templink.created_at + TempFileDownloadCleanup::DEFAULT_THRESHOLD.minutes
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_study
    @study = Study.find(params[:id])
  end

  # study params whitelist
  def study_params
    params.require(:study).permit(:name, :description, :public, :user_id, :embargo, :cell_count, study_files_attributes: [:id, :_destroy, :name, :path, :upload, :description, :file_type, :status], study_shares_attributes: [:id, :_destroy, :email, :permission])
  end

  # study file params whitelist
  def study_file_params
    params.require(:study_file).permit(:_id, :study_id, :name, :upload, :description, :file_type, :status, :human_fastq_url, :human_data, :cluster_type)
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

  # set up variables for wizard
  def intitialize_wizard_files
    @assignment_file = @study.cluster_assignment_file
    @parent_cluster = @study.parent_cluster_coordinates_file
    @expression_file = @study.expression_matrix_file
    @sub_clusters = @study.study_files.select {|sf| sf.file_type == 'Cluster Coordinates' && sf.cluster_type == 'sub'}
    @marker_lists = @study.study_files.select {|sf| sf.file_type == 'Gene List'}
    @fastq_files = @study.study_files.select {|sf| sf.file_type == 'Fastq'}
    @other_files = @study.study_files.select {|sf| %w(Documentation Other).include?(sf.file_type)}

    # if files don't exist, build them for use later
    if @assignment_file.nil?
      @assignment_file = @study.build_study_file({file_type: 'Cluster Assignments'})
    end
    if @parent_cluster.nil?
      @parent_cluster = @study.build_study_file({file_type: 'Cluster Coordinates', cluster_type: 'parent'})
    end
    if @sub_clusters.empty?
      @sub_clusters << @study.build_study_file({file_type: 'Cluster Coordinates', cluster_type: 'sub'})
    end
    if @expression_file.nil?
      @expression_file = @study.build_study_file({file_type: 'Expression Matrix'})
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
