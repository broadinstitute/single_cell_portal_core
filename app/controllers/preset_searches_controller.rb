class PresetSearchesController < ApplicationController
  before_action :set_preset_search, only: [:show, :edit, :update, :destroy]
  before_action do
    authenticate_user!
    authenticate_admin
  end
  before_action :check_read_only_mode!, except: [:index, :show]

  # GET /preset_searches
  # GET /preset_searches.json
  def index
    @preset_searches = PresetSearch.all
  end

  # GET /preset_searches/1
  # GET /preset_searches/1.json
  def show
  end

  # GET /preset_searches/new
  def new
    @preset_search = PresetSearch.new
  end

  # GET /preset_searches/1/edit
  def edit
  end

  # POST /preset_searches
  # POST /preset_searches.json
  def create
    serialized_params = serialize_preset_search_params
    @preset_search = PresetSearch.new(serialized_params)

    respond_to do |format|
      if @preset_search.save
        format.html { redirect_to @preset_search, notice: 'Stored search was successfully created.' }
        format.json { render :show, status: :created, location: @preset_search }
      else
        format.html { render :new }
        format.json { render json: @preset_search.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /preset_searches/1
  # PATCH/PUT /preset_searches/1.json
  def update
    serialized_params = serialize_preset_search_params
    respond_to do |format|
      if @preset_search.update(serialized_params)
        format.html { redirect_to @preset_search, notice: 'Stored search was successfully updated.' }
        format.json { render :show, status: :ok, location: @preset_search }
      else
        format.html { render :edit }
        format.json { render json: @preset_search.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /preset_searches/1
  # DELETE /preset_searches/1.json
  def destroy
    @preset_search.destroy
    respond_to do |format|
      format.html { redirect_to preset_searches_url, notice: 'Stored search was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_preset_search
    @preset_search = PresetSearch.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the permit list through.
  def preset_search_params
    params.require(:preset_search).permit(:name, :public, :accession_list, :search_terms, :facet_filters)
  end

  # convert text fields into arrays for saving
  # TODO: figure out a way to leverage this natively using array serialization w/ forms because this is gross as hell
  def serialize_preset_search_params
    form_params = preset_search_params.to_unsafe_hash
    accessions = form_params[:accession_list].blank? ? [] : form_params[:accession_list].split.map(&:strip)
    facets = form_params[:facet_filters].blank? ? [] : form_params[:facet_filters].split('+').map(&:strip)
    terms = []
    if form_params[:search_terms].present? && form_params[:search_terms].include?("\"")
      form_params[:search_terms].split("\"").each do |substring|
        if substring.start_with?(' ') || substring.end_with?(' ')
          terms += substring.strip.split
        else
          terms << substring
        end
      end
    else
      terms = form_params[:search_terms].split if form_params[:search_terms].present?
    end
    form_params[:search_terms] = terms.map(&:strip).delete_if(&:blank?)
    form_params[:accession_list] = accessions
    form_params[:facet_filters] = facets
    form_params
  end
end
