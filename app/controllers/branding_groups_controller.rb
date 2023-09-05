class BrandingGroupsController < ApplicationController
  before_action :set_branding_group, only: [:show, :edit, :update, :destroy]
  before_action except: [:list_navigate] do
    authenticate_user!
  end

  before_action :authenticate_curator, only: [:show, :edit, :update]
  before_action :authenticate_admin, only: [:index, :create, :destroy]

  # GET /branding_groups
  # GET /branding_groups.json
  def index
    @branding_groups = BrandingGroup.all
  end

  # show a list for display and linking, editable only if the user has appropriate permissions
  def list_navigate
    @branding_groups = BrandingGroup.visible_groups_to_user(current_user)
  end

  # GET /branding_groups/1
  # GET /branding_groups/1.json
  def show
  end

  # GET /branding_groups/new
  def new
    @branding_group = BrandingGroup.new
  end

  # GET /branding_groups/1/edit
  def edit
  end

  # POST /branding_groups
  # POST /branding_groups.json
  def create
    clean_params = branding_group_params.to_h
    users = self.class.find_users_from_emails(params[:curator_emails], nil, current_user)
    clean_params[:user_ids] = users.map(&:id)
    studies = self.class.find_studies_from_accessions(params[:study_accessions], current_user)
    clean_params[:study_ids] = studies.map(&:id)
    missing_studies = self.class.get_missing_studies(
      self.class.param_to_array(params[:study_accessions]), studies
    )
    @branding_group = BrandingGroup.new(clean_params)

    respond_to do |format|
      if @branding_group.save
        notice = "Successfully updated collection \"#{@branding_group.name}\""
        if missing_studies.any?
          notice += " #{missing_studies.join(', ')} could not be added to this collection."
        end
        # push all branding assets to remote to ensure consistency
        UserAssetService.delay.push_assets_to_remote(asset_type: :branding_images)
        format.html do
          redirect_to merge_default_redirect_params(branding_group_path(@branding_group), scpbr: params[:scpbr]),
                      notice:
        end
        format.json { render :show, status: :created, location: @branding_group }
      else
        format.html { render :new }
        format.json { render json: @branding_group.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /branding_groups/1
  # PATCH/PUT /branding_groups/1.json
  def update
    respond_to do |format|
      clean_params = branding_group_params.to_h
      # iterate through each image type to check if the user wants to clear it from the reset checkbox
      ['splash_image', 'banner_image', 'footer_image'].each do |image_name|
        if clean_params["reset_#{image_name}"] == 'on'
          clean_params[image_name] = nil
        end
        # delete the param since it is not a real model param
        clean_params.delete("reset_#{image_name}")
      end

      # merge in curator and study params
      users = self.class.find_users_from_emails(
        params[:curator_emails], @branding_group, current_user
      )
      clean_params[:user_ids] = users.map(&:id)

      studies = self.class.find_studies_from_accessions(
        params[:study_accessions], current_user
      )
      clean_params[:study_ids] = studies.map(&:id)
      missing_studies = self.class.get_missing_studies(
        self.class.param_to_array(params[:study_accessions]), studies
      )

      if @branding_group.update(clean_params)
        notice = "Successfully updated collection \"#{@branding_group.name}\""
        if missing_studies.any?
          notice += " #{missing_studies.join(', ')} could not be added to this collection."
        end
        format.html do
          redirect_to merge_default_redirect_params(branding_group_path(@branding_group), scpbr: params[:scpbr]),
                      notice:
        end
        format.json { render :show, status: :ok, location: @branding_group }
      else
        format.html { render :edit }
        format.json { render json: @branding_group.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /branding_groups/1
  # DELETE /branding_groups/1.json
  def destroy
    name = @branding_group.name
    @branding_group.destroy
    respond_to do |format|
      format.html { redirect_to merge_default_redirect_params(branding_groups_path, scpbr: params[:scpbr]),
                                notice: "Collection '#{name}' was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  # helper to merge in the list of curators into the :users parameter
  # will prevent curator from removing themselves from the collection
  def self.find_users_from_emails(curator_list, collection, user)
    curators = param_to_array(curator_list)
    users = curators.map { |email| User.find_by(email: email) }.compact
    return users if collection.nil?

    # ensure current user cannot accidentally remove themselves from the list if this is an update
    users << user if collection.users.include?(user) && !users.include?(user)
    users
  end

  # allow mass assignment of studies from collection edit view
  def self.find_studies_from_accessions(study_list, user)
    accessions = param_to_array(study_list)
    # skip checking group shares for performance reasons
    Study.where(:accession.in => accessions).select { |study| study.can_view?(user, check_groups: false) }
  end

  # convert a comma- or space-delimited string to an array of strings, removing empty values
  def self.param_to_array(param)
    param.split(/[,\s]/).map(&:strip).reject(&:blank?)
  end

  # detect which studies could not be saved (either don't exist or curator does't have permission)
  def self.get_missing_studies(original_accessions, studies)
    original_accessions - studies.map(&:accession)
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_branding_group
    @branding_group = BrandingGroup.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the permit list through.
  def branding_group_params
    params.require(:branding_group).permit(:name, :tag_line, :public, :background_color, :font_family, :font_color,
                                           :splash_image, :banner_image, :footer_image, :external_link_url, :external_link_description,
                                           :reset_splash_image, :reset_footer_image, :reset_banner_image, :user_ids,
                                           :study_ids)
  end

  def authenticate_curator
    unless @branding_group.can_edit?(current_user)
      redirect_to collection_list_navigate_path, alert: 'You do not have permission to perform that action' and return
    end
  end
end
