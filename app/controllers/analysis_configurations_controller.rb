class AnalysisConfigurationsController < ApplicationController
  before_action :set_analysis_configuration, only: [:show, :edit, :update, :destroy, :reset_analysis_parameters,
                                                    :submission_preview, :load_study_for_submission_preview,
                                                    :update_analysis_parameter]
  before_action :set_analysis_parameter, only: [:update_analysis_parameter]
  before_action :check_firecloud_status, only: [:new, :create]
  before_action do
    authenticate_user!
    authenticate_admin
  end

  # GET /analysis_configurations
  # GET /analysis_configurations.json
  def index
    @analysis_configurations = AnalysisConfiguration.all
  end

  # GET /analysis_configurations/1
  # GET /analysis_configurations/1.json
  def show
    @inputs = @analysis_configuration.analysis_parameters.inputs
    @outputs = @analysis_configuration.analysis_parameters.outputs
  end

  # GET /analysis_configurations/new
  def new
    @analysis_configuration = AnalysisConfiguration.new(user: current_user)
  end

  # POST /analysis_configurations
  # POST /analysis_configurations.json
  def create
    @analysis_configuration = AnalysisConfiguration.new(analysis_configuration_params)

    respond_to do |format|
      if @analysis_configuration.save
        format.html { redirect_to @analysis_configuration, notice: "'#{@analysis_configuration.identifier}' was successfully created." }
        format.json { render :show, status: :created, location: @analysis_configuration }
      else
        format.html { render :new }
        format.json { render json: @analysis_configuration.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /analysis_configurations/1
  # PATCH/PUT /analysis_configurations/1.json
  def update
    respond_to do |format|
      if @analysis_configuration.update(analysis_configuration_params)
        format.html { redirect_to @analysis_configuration, notice: "'#{@analysis_configuration.identifier}' was successfully updated." }
        format.json { render :show, status: :ok, location: @analysis_configuration }
      else
        format.html { render :edit }
        format.json { render json: @analysis_configuration.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /analysis_configurations/1
  # DELETE /analysis_configurations/1.json
  def destroy
    identifier = @analysis_configuration.identifier
    @analysis_configuration.destroy
    respond_to do |format|
      format.html { redirect_to analysis_configurations_url, notice: "'#{identifier}' was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  # PATCH /analysis_configurations/:id/analysis_parameters/:analysis_parameter_id
  def update_analysis_parameter
    respond_to do |format|
      if @analysis_parameter.update(analysis_parameter_params)
        format.js { render :update_analysis_parameter }
        format.json { render :show, status: :ok, location: @analysis_parameter }
      else
        format.js { render :update_analysis_parameter }
        format.json { render json: @analysis_parameter.errors, status: :unprocessable_entity }
      end
    end
  end

  # clear out any saved input/output parameters and set directly from WDL
  def reset_analysis_parameters
    @analysis_configuration.load_parameters_from_wdl!
    redirect_to analysis_configuration_path(@analysis_configuration), notice: "'#{@analysis_configuration.identifier}' parameters successfully reset."
  end

  # load options for associated model
  def load_associated_model
    associated_model = params[:model]
    model_attributes = {}
    begin
      model = associated_model.constantize
      AnalysisParameter::ASSOCIATED_MODEL_ATTR_NAMES.each do |constant_name|
        model_attributes[constant_name.downcase.to_s] = model.const_defined?(constant_name) ? model.const_get(constant_name) : []
      end
    rescue => e
      error_context = ErrorTracker.format_extra_context({params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      logger.error "Error loading associated model due to error: #{e.message}"
    end
    render json: model_attributes.to_json
  end

  def load_associated_model_filter_types
    associated_model = params[:model]
    model_filters = {}
    begin
      model = associated_model.constantize
      model_filters= []
      if model.const_defined?(:ANALYSIS_PARAMETER_FILTERS)
        model_filters = model.const_get(:ANALYSIS_PARAMETER_FILTERS).keys
      end
    rescue => e
      error_context = ErrorTracker.format_extra_context({params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      logger.error "Error loading associated model due to error: #{e.message}"
    end
    render json: model_filters.to_json
  end

  def load_associated_model_filter_values
    associated_model = params[:model]
    filter_attr = params[:filter]
    model_filters = {}
    begin
      model = associated_model.constantize
      model_filters = []
      if model.const_defined?(:ANALYSIS_PARAMETER_FILTERS)
        model_filters = model.const_get(:ANALYSIS_PARAMETER_FILTERS)[filter_attr]
      end
    rescue => e
      error_context = ErrorTracker.format_extra_context({params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      logger.error "Error loading associated model due to error: #{e.message}"
    end
    render json: model_filters.to_json
  end

  # preview submission form for a given analysis and study
  def submission_preview
    # load a random study, or use selected study
    @studies = Study.where(public: true).pluck(:name, :id)
  end

  def load_study_for_submission_preview
    @study = Study.find(params[:study][:id])
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_analysis_configuration
      @analysis_configuration = AnalysisConfiguration.find(params[:id])
    end

    def set_analysis_parameter
      @analysis_parameter = AnalysisParameter.find_by(id: params[:analysis_parameter_id], analysis_configuration_id: params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def analysis_configuration_params
      params.require(:analysis_configuration).permit(:namespace, :name, :snapshot, :configuration_namespace,
                                                     :configuration_name, :configuration_snapshot, :user_id, :description,
                                                     external_resources_attributes: [:id, :_destroy, :title, :description,
                                                                                     :url, :publication_url])
    end

    def analysis_parameter_params
      params.require(:analysis_parameter).permit(:id, :data_type, :call_name, :parameter_type, :parameter_name,
                                                 :parameter_value, :optional, :associated_model, :associated_model_method,
                                                 :associated_model_display_method, :association_filter_attribute,
                                                 :association_filter_value, :output_file_type, :description, :visible,
                                                 :apply_to_all, :is_reference_bundle,
                                                 analysis_parameter_filters_attributes: [:id, :attribute_name, :value,
                                                                                         :multiple, :_destroy, :multiple_values => []],
                                                 analysis_output_associations_attributes: [:id, :attribute_name,
                                                                                           :attribute_value, :association_source,
                                                                                           :association_method, :association_data_type,
                                                                                           :_destroy])
    end

    def check_firecloud_status
      unless ApplicationController.firecloud_client.services_available?(FireCloudClient::RAWLS_SERVICE)
        alert = 'The Methods Repository is temporarily unavailable, so we cannot complete your request.  Please try again later.'
        respond_to do |format|
          format.js {render js: "$('.modal').modal('hide'); alert('#{alert}')" and return}
          format.html {redirect_to merge_default_redirect_params(studies_path, scpbr: params[:scpbr]),
                                   alert: alert and return}
          format.json {head 503}
        end
      end
    end
end
