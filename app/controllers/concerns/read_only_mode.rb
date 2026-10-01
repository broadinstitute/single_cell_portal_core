module ReadOnlyMode
  extend ActiveSupport::Concern

  def check_read_only_mode!
    if read_only_mode?
      redirect_to site_path, alert: "The portal is currently in read-only mode, meaning all study updates are blocked.  We apologize for any inconvenience." and return
    end
  end

  def read_only_mode?
    if user_signed_in?
      current_user.feature_flag_for('read_only_mode')
    else
      feature_flag = FeatureFlag.find_by(name: 'read_only_mode')
      feature_flag&.default_value || false
    end
  end
end
