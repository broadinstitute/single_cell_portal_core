class AddFlagForDotPlotPreprocessing < Mongoid::Migration
  def self.up
    FeatureFlag.create!(name: 'dot_plot_preprocessing',
                        default_value: false,
                        description: 'automate preprocessing of dot plot genes')
  end

  def self.down
    FeatureFlag.retire_feature_flag('dot_plot_preprocessing')
  end
end
