class AbTestsController < ApplicationController
  before_action do
    authenticate_user!
    authenticate_admin
    set_feature_flag
  end

  before_action :set_ab_test, except: :create

  def create
    @feature_flag.build_ab_test.save! if @feature_flag.ab_test.nil?
    redirect_to edit_feature_flag_ab_test_path
  end

  def edit; end

  def update
    if @ab_test.update(ab_test_params)
      redirect_to edit_feature_flag_ab_test_path, notice: 'A/B test successfully updated'
    else
      render action: :edit
    end
  end

  def destroy
    @ab_test.destroy
    redirect_to feature_flag_options_path, notice: 'A/B test successfully destroyed'
  end

  def add_to_group
    # clear feature_flag_option first
    current_user.remove_flag_option(@feature_flag.name)
    # add user to A/B test group assignment
    @assignment = @ab_test.assignment(current_user.metrics_uuid)
    if @assignment.update(group_name: params[:group_name])
      redirect_to edit_feature_flag_ab_test_path, notice: 'Successfully added to group'
    else
      redirect_to edit_feature_flag_ab_test_path,
                  alert: "Could not add to group: #{@assignment.errors.full_messages.join(', ')}"
    end
  end

  private

  def set_feature_flag
    @feature_flag = FeatureFlag.find_by(name: params[:name])
  end

  def set_ab_test
    @ab_test = @feature_flag.ab_test
  end

  def ab_test_params
    params.require(:ab_test).permit(:enabled, group_names: [])
  end
end
