class AddDotPlotPreprocessingFrontendFeatureFlag < Mongoid::Migration
  def self.up
    FeatureFlag.find_or_create_by(name: 'dot_plot_preprocessing_frontend') do |flag|
      flag.default_value = false
      flag.description = 'Enable pre-computed dot plot data from backend preprocessing'
    end
  end

  def self.down
    flag = FeatureFlag.find_by(name: 'dot_plot_preprocessing_frontend')
    flag.destroy if flag.present?
  end
end
