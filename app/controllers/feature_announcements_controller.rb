class FeatureAnnouncementsController < ApplicationController
  before_action :authenticate_user!, except: %i[latest view_announcement]
  before_action :authenticate_admin, except: %i[latest view_announcement]
  before_action :set_feature_announcement, only: %i[edit update destroy]
  before_action :check_read_only_mode!, except: [:index, :show, :latest, :view_announcement]

  def latest
    @latest = FeatureAnnouncement.latest.order(created_at: :desc)
    @archived = FeatureAnnouncement.archived.order(created_at: :desc)
  end

  def view_announcement
    @feature_announcement = FeatureAnnouncement.find_by(slug: params[:slug])
  end

  # GET /feature_announcements or /feature_announcements.json
  def index
    @feature_announcements = FeatureAnnouncement.all
  end

  # GET /feature_announcements/new
  def new
    @feature_announcement = FeatureAnnouncement.new
  end

  # GET /feature_announcements/1/edit
  def edit
  end

  # POST /feature_announcements or /feature_announcements.json
  def create
    @feature_announcement = FeatureAnnouncement.new(feature_announcement_params)

    respond_to do |format|
      if @feature_announcement.save
        format.html { redirect_to feature_announcements_path, notice: "#{@feature_announcement.title} was successfully created." }
        format.json { render :index, status: :created }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @feature_announcement.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /feature_announcements/1 or /feature_announcements/1.json
  def update
    respond_to do |format|
      if @feature_announcement.update(feature_announcement_params)
        format.html { redirect_to feature_announcements_path, notice: "#{@feature_announcement.title} was successfully updated." }
        format.json { render :index, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @feature_announcement.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /feature_announcements/1 or /feature_announcements/1.json
  def destroy
    title = @feature_announcement.title.dup
    @feature_announcement.destroy
    respond_to do |format|
      format.html { redirect_to feature_announcements_url, notice: "#{title} was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_feature_announcement
    @feature_announcement = FeatureAnnouncement.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def feature_announcement_params
    params.require(:feature_announcement).permit(:title, :content, :doc_link, :published, :archived)
  end
end
