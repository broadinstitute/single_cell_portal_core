class RetireShowExploreTabUxUpdatesFeatureFlag < Mongoid::Migration
  def self.up
    FeatureFlag.retire_feature_flag('show_explore_tab_ux_updates')
  end

  def self.down
    FeatureFlag.create!(name: 'show_explore_tab_ux_updates',
                        default_value: false,
                        description: 'show the "Update the Explore Tab" epic changes')
  end
end
