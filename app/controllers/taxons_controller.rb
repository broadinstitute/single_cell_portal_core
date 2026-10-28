class TaxonsController < ApplicationController
  before_action :set_taxon, except: [:index, :new, :create, :download_genome_annotation, :upload_species_list]
  before_action do
    authenticate_user!
    authenticate_admin
  end
  before_action :check_read_only_mode!, except: [:index, :show, :download_genome_annotation]

  # GET /taxons
  # GET /taxons.json
  def index
    @taxons = Taxon.all
  end

  # GET /taxons/1
  # GET /taxons/1.json
  def show
  end

  # GET /taxons/new
  def new
    @taxon = Taxon.new(user_id: current_user.id)
  end

  # GET /taxons/1/edit
  def edit
  end

  # POST /taxons
  # POST /taxons.json
  def create
    @taxon = Taxon.new(taxon_params)

    respond_to do |format|
      if @taxon.save
        format.html { redirect_to taxon_path(@taxon), notice: "Species: '#{@taxon.common_name}' was successfully created." }
        format.json { render :show, status: :created, location: @taxon }
      else
        format.html { render :new }
        format.json { render json: @taxon.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /taxons/1
  # PATCH/PUT /taxons/1.json
  def update
    respond_to do |format|
      if @taxon.update(taxon_params)
        format.html { redirect_to taxons_path, notice: "Species: '#{@taxon.common_name}' was successfully updated." }
        format.json { render :show, status: :ok, location: @taxon }
      else
        format.html { render :edit }
        format.json { render json: @taxon.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /taxons/1
  # DELETE /taxons/1.json
  def destroy
    common_name = @taxon.common_name
    @taxon.destroy
    respond_to do |format|
      format.html { redirect_to taxons_path, notice: "Species: '#{common_name}' was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def download_genome_annotation
    genome_annotation = GenomeAnnotation.find(params[:id])
    annotation_link = genome_annotation.annotation_download_link
    if annotation_link.present?
      redirect_to annotation_link and return
    else
      redirect_to taxons_path, alert: "Unable to generate a public link for '#{@taxon.genome_annotation_link}'.  Please try again."
    end
  end

  # upload a file of species/assemblies to auto-populate
  def upload_species_list
    begin
      species_upload = params[:upload]
      new_records = Taxon.parse_from_file(species_upload, current_user)
      redirect_to taxons_path, notice: "Upload successful - new/updated species added: #{new_records[:new_species]}, new/updated assemblies added: #{new_records[:new_assemblies]}, new/updated annotations added: #{new_records[:new_annotations]}"
    rescue => e
      ErrorTracker.report_exception(e, current_user, @study, params)
      Rails.logger.error "Error parsing uploaded species file: #{e.message}"
      redirect_to taxons_path, alert: "An error occurred while parsing the uploaded file: #{e.message}"
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_taxon
      @taxon = Taxon.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the permit list through.
    def taxon_params
      params.require(:taxon).permit(:common_name, :scientific_name, :ncbi_taxid, :user_id, :notes, :aliases, :restricted,
                                    genome_assemblies_attributes: [:id, :name, :alias, :accession, :release_date, :_destroy,
                                    genome_annotations_attributes: [:id, :name, :link, :index_link, :release_date,
                                    :_destroy]])
    end
end
