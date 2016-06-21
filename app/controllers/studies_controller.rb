class StudiesController < ApplicationController
  before_action :set_study, only: [:show, :edit, :update, :initialize_study, :destroy, :upload, :do_upload, :resume_upload, :update_status, :reset_upload, :new_study_file, :update_study_file, :delete_study_file, :retrieve_upload, :parse, :launch_parse_job]
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
    @assignment_file = StudyFile.find_or_create_by({study_id: @study._id, file_type: 'Cluster Assignments'})
    @parent_cluster = StudyFile.find_or_create_by({study_id: @study._id, file_type: 'Cluster Coordinates', cluster_type: 'parent'})
    @expression_file = StudyFile.find_or_create_by({study_id: @study._id, file_type: 'Expression Matrix'})
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
    logger.info "PARSING"
    @study_file = StudyFile.where(study_id: params[:id], upload_file_name: params[:file]).first
    begin
      case @study_file.file_type
        when 'Cluster Coordinates'
          @study.make_cluster_points(@study.cluster_assignment_file, @study_file, @study_file.cluster_type)
        when 'Expression Matrix'
          @study.make_expression_scores(@study_file)
        when 'Marker Gene List'
          @study.make_precomputed_scores(@study_file, params[:list_name])
      end
    rescue StandardError => e
      logger.error "ERROR: #{e.message}"
      @error = e.message
      # remove bad study file, reload good entries
      @study_file.destroy
      @parent_cluster = StudyFile.find_or_create_by({study_id: @study._id, file_type: 'Cluster Coordinates', cluster_type: 'parent'})
      @expression_file = StudyFile.find_or_create_by({study_id: @study._id, file_type: 'Expression Matrix'})
      render 'parse_error'
    end
  end

  # launches parse job via delayed_job
  def launch_parse_job
    if params.include?(:clusters)
      assignment_file = @study.cluster_assignment_file
      cluster_file = @study.study_files.where(name: clusters_params[:cluster_file]).first
      # queue delayed job to parse clusters using ClusterFileParseJob class for error handling & emails
      Delayed::Job.enqueue ClusterFileParseJob.new(@study, assignment_file, cluster_file, clusters_params[:cluster_type], current_user)
      logger.info "Launching parse job on study id: '#{@study.name}', parse_type: 'clusters', file: '#{cluster_file.name}', cluster_type: '#{clusters_params[:cluster_type]}'"
      @message = "Cluster file: #{clusters_params[:cluster_file]} is now being parsed.  You will receive an email when this has completed with the details."
      @target = "##{cluster_file._id}_parse"
    end
    if params.include?(:expression)
      expression_file = @study.study_files.where(name: expression_params[:expression_file]).first
      # queue delayed job
      Delayed::Job.enqueue ExpressionFileParseJob.new(@study, expression_file, current_user)
      logger.info "Launching parse job on study id: '#{@study.name}', parse_type: 'expression', file: '#{expression_file.name}'"
      @message = "Expression matrix file: #{expression_params[:expression_file]} is now being parsed.  You will receive an email when this has completed with the details."
      @target = "##{expression_file._id}_parse"
    end
    if params.include?(:precomputed)
      precomputed_file = @study.study_files.where(name: precomputed_params[:precomputed_file]).first
      # queue delayed job
      Delayed::Job.enqueue MarkerFileParseJob.new(@study, precomputed_file, precomputed_params[:precomputed_name], current_user)
      logger.info "Launching parse job on study id: '#{@study.name}', parse_type: 'marker_genes', file: '#{precomputed_file.name}', list_name: '#{precomputed_params[:precomputed_name]}'"
      @message = "Marker gene list file: #{precomputed_params[:precomputed_file]} is now being parsed.  You will receive an email when this has completed with the details."
      @target = "##{precomputed_file._id}_parse"
    end
  end

  # upload study files to study
  def upload
    @study_files = @study.study_files.sort_by(&:created_at)
  end

  # create a new study_file for requested study
  def new_study_file
    file_type = params[:file_type] ? params[:file_type] : 'Cluster Assignments'
    @study_file = @study.study_files.build(file_type: file_type)
  end

  # update an existing study file; cannot be called until file is uploaded, so there is no create
  # if adding an external fastq file link, will create entry from scratch to update
  def update_study_file
    @study_file = StudyFile.where(study_id: study_file_params[:study_id], name: study_file_params[:name]).first
    if @study_file.nil?
      @study_file = @study.study_files.build
    end
    @study_file.update_attributes(study_file_params)
    @message = "'#{@study_file.name}' has been successfully updated."
  end

  # delete the requested study file
  def delete_study_file
    @study_file = StudyFile.find(params[:study_file_id])
    unless @study_file.nil?
      @message = "'#{@study_file.name}' has been successfully deleted."
      @study_file.destroy
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
      # Add the following chunk to the incomplete upload
      File.open(study_file.upload.path, "ab") { |f| f.write(upload.read) }

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
    unless study_file.nil?
      render json: { file: { name: study_file.upload.url, size: study_file.upload_file_size } } and return
    else
      render json: { file: { name: "/uploads/default/missing.png",size: nil } } and return
    end
  end

  # PATCH /courses/:id/update_upload_status
  def update_status
    study_file = StudyFile.where(study_id: params[:id], name: params[:file]).first
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
    case params[:object]
      when 'assignment_file'
        @assignment_file = StudyFile.where(study_id: params[:id], upload_file_name: params[:file]).first
      when 'cluster_file'

      when 'expression_file'

      else
        @study_file = StudyFile.where(study_id: params[:id], upload_file_name: params[:file]).first
    end
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
    params.require(:study).permit(:name, :description, :public, :user_id, :embargo, study_files_attributes: [:id, :_destroy, :name, :path, :upload, :description, :file_type, :status], study_shares_attributes: [:id, :_destroy, :email, :permission])
  end

  # study file params whitelist
  def study_file_params
    params.require(:study_file).permit(:_id, :study_id, :name, :upload, :description, :file_type, :status, :human_fastq_url, :human_data)
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
end
