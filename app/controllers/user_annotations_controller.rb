class UserAnnotationsController < ApplicationController

  ###
  #
  # FILTERS AND SETTINGS
  #
  ###

  before_action :set_user_annotation, only: [:edit, :update, :destroy]
  before_action :authenticate_user!
  before_action :check_permission, except: [:index, :find_annotation]

  ###
  #
  # USERANNOTATION OBJECT METHODS
  # (show and create are removed as they are implemented in the SiteController)
  #
  ###

  # GET /user_annotations
  # GET /user_annotations.json
  def index
    # get all this user's annotations
    @user_annotations = UserAnnotation.viewable(current_user).paginate(page: params[:page], per_page: 25)
  end

  def find_annotation
    @user_annotations = UserAnnotation.viewable(current_user).select do |annotation|
      annotation.name =~ /#{params[:annotation_name]}/i
    end.paginate(page: params[:page], per_page: 25)

    render action: :index
  end

  # GET /user_annotations/1/edit
  def edit

  end

  # PATCH/PUT /user_annotations/1
  # PATCH/PUT /user_annotations/1.json
  def update
    # check if any changes were made to sharing for notifications
    if !user_annotation_params[:user_annotation_shares_attributes].nil?
      @share_changes = @user_annotation.user_annotation_shares.count != user_annotation_params[:user_annotation_shares_attributes].keys.size
      user_annotation_params[:user_annotation_shares_attributes].values.each do |share|
        if share["_destroy"] == "1"
          @share_changes = true
        end
      end
    else
      @share_changes = false
    end
    # update the annotation's defined labels
    new_labels = user_annotation_params.to_h['values']
    # If the labels sued to include undefined, make sure they do again
    if @user_annotation.values.include? 'Undefined'
      new_labels.push('Undefined')
    end

    # Remember the old values
    old_labels = @user_annotation.values

    # Remember the old annotations
    annotation_arrays = @user_annotation.user_data_arrays.all_by_name_and_type(@user_annotation.name,'annotations')

    respond_to do |format|
      #if a successful update, update data arrays
      if @user_annotation.update(user_annotation_params)
        # first, invalidate matching caches
        CacheRemovalJob.new(@user_annotation.cache_removal_key).delay(queue: :cache).perform
        changes = []
        if @share_changes
          changes << 'Annotation shares'
        end
        if @user_annotation.user_annotation_shares.any?
          SingleCellMailer.annot_share_update_notification(@user_annotation, changes, current_user).deliver_now
        end
        #this is per annotation array-- each annotation array is a different subsampling level
        annotation_arrays.each do |annot|
          #remember the index of old labels, this is per annotation
          old_values = annot.values

          #remember all the old indices and their labels
          index_of_values = []
          old_labels.each_with_index do |old, i|
            index_array = []
            old_values.each_with_index do |value, i|
              if value == old
                index_array.push(i)
              end
            end
            index_of_values.push(index_array)
          end

          #index of values remembers what the order of the old annotations was
          index_of_values.each_with_index do |old_index, i|
            old_index.each do |index|
              old_values[index] = new_labels[i]
            end
          end

          #update the annotations with new values
          annot.update(values: old_values, name: user_annotation_params.to_h['name'])

        end

        #If successful, redirect back and say success
        format.html { redirect_to merge_default_redirect_params(user_annotations_path, scpbr: params[:scpbr]),
                                  notice: "User Annotation '#{@user_annotation.name}' was successfully updated." }
        format.json { render :index, status: :ok, location: user_annotations_path }
      else
        #If an error, show it
        format.html { render :edit }
        format.json { render json: @user_annotation.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /user_annotations/1
  # DELETE /user_annotations/1.json
  def destroy
    # set queued_for_deletion manually - gotcha due to race condition on page reloading and how quickly delayed_job can process jobs
    @user_annotation.update(queued_for_deletion: true)

    # queue jobs to delete annotation caches & annotation itself
    CacheRemovalJob.new(@user_annotation.cache_removal_key).delay(queue: :cache).perform
    DeleteQueueJob.new(@user_annotation).delay.perform

    # notify users of deletion before removing shares & owner
    SingleCellMailer.annotation_delete_notification(@user_annotation, current_user).deliver_now

    # revoke all user annotation shares
    @user_annotation.user_annotation_shares.delete_all
    update_message = "User Annotation '#{@user_annotation.name}'was successfully destroyed. All parsed database records have been destroyed."
    respond_to do |format|
      #redirect back to page when destroy finishes
      format.html { redirect_to merge_default_redirect_params(user_annotations_path, scpbr: params[:scpbr]),
                                notice: update_message }
      format.json { head :no_content }
    end
  end

  def download_user_annotation
    cluster_name = @user_annotation.cluster_group.name
    filename = (cluster_name + '_' + @user_annotation.name + '.txt').gsub(/ /, '_')
    headers = ['NAME', 'X', 'Y', @user_annotation.name]
    types = ['TYPE', 'numeric', 'numeric', 'group']
    rows = []

    annotation_array = @user_annotation.concatenate_data_arrays(@user_annotation.name ,'annotations')
    x_array = @user_annotation.concatenate_data_arrays('x', 'coordinates')
    y_array = @user_annotation.concatenate_data_arrays('y', 'coordinates')
    cell_name_array = @user_annotation.concatenate_data_arrays('text', 'cells')

    annotation_array.each_with_index do |annot, index|
      if annot != 'Undefined'
        row = []
        row << cell_name_array[index]
        row << x_array[index]
        row << y_array[index]
        row << annot
        rows << row.join("\t")
      end

    end
    @data = [headers.join("\t"), types.join("\t"), rows].join"\n"

    send_data @data, type: 'text/plain', filename: filename, disposition: 'attachment'
  end

  def publish_to_study
    respond_to do |format|
      # set publishing status to true so that the annotation will not show up in the list of annotations
      @user_annotation.update(publishing: true)
      # redirect back and say success
      format.html { redirect_to merge_default_redirect_params(user_annotations_path, scpbr: params[:scpbr]),
                                notice: "User Annotation '#{@user_annotation.name}' will be added to the study. You will receive an email upon completion or error. If succesful, this annotation will be removed from your list of annotations." }
      format.json { render :index, status: :ok, location: user_annotations_path }
      @user_annotation.delay.publish_to_study(current_user)
    end
  end

  private

  ###
  #
  # SETTERS
  #
  ###

  # Use callbacks to share common setup or constraints between actions.
  def set_user_annotation
    @user_annotation = UserAnnotation.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the permit list through.
  # permit parameters for creating custom user annotation
  def user_annotation_params
    params.require(:user_annotation).permit(:_id, :name, :study_id, :user_id, :cluster_group_id, values: [],
                                            user_annotation_shares_attributes: [:id, :_destroy, :email, :permission])
  end

  # checks that current user id is the same as annotation being edited or destroyed
  def check_permission
    if @user_annotation.nil?
      @user_annotation = UserAnnotation.find(params[:id])
    end
    if !@user_annotation.can_edit?(current_user)
      redirect_to merge_default_redirect_params(user_annotations_path, scpbr: params[:scpbr]),
                  alert: "You don't have permission to perform that action.  #{SCP_SUPPORT_EMAIL}"
    end
  end
end
