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
    clean_params[:users] = self.class.merge_curator_params(params[:curator_emails], nil, current_user)
    clean_params.delete(:user_ids)
    clean_params[:studies] = self.class.merge_study_params(params[:study_accessions], current_user)
    clean_params.delete(:study_ids)
    @branding_group = BrandingGroup.new(clean_params)

    respond_to do |format|
      if @branding_group.save
        # push all branding assets to remote to ensure consistency
        UserAssetService.delay.push_assets_to_remote(asset_type: :branding_images)
        format.html { redirect_to merge_default_redirect_params(branding_group_path(@branding_group), scpbr: params[:scpbr]),
                                  notice: "Collection '#{@branding_group.name}' was successfully created." }
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

        # merge in curator and study params
        clean_params[:users] = self.class.merge_curator_params(
          params[:curator_emails], @branding_group, current_user
        )
        clean_params.delete(:user_ids)
        clean_params[:studies] = self.class.merge_study_params(
          params[:study_accessions], current_user
        )
        clean_params.delete(:study_ids)
      end

      if @branding_group.update(clean_params)
        format.html { redirect_to merge_default_redirect_params(branding_group_path(@branding_group), scpbr: params[:scpbr]),
                                  notice: "Collection '#{@branding_group.name}' was successfully updated." }
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
  def self.merge_curator_params(curator_list, collection, user)
    curators = curator_list.split(',').map(&:strip)
    users = curators.map { |email| User.find_by(email: email) }.compact
    return users if collection.nil?

    # ensure current user cannot accidentally remove themselves from the list if this is an update
    users << user if collection.users.include?(user) && !users.include?(user)
    users
  end

  # allow mass assignment of studies from collection edit view
  def self.merge_study_params(study_list, user)
    accessions = study_list.split(',').map(&:strip)
    # skip checking group shares for performance reasons
    Study.where(:accession.in => accessions).select { |study| study.can_view?(user, check_groups: false) }
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
