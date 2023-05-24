  class RetireExploreTabDefaultFeatureFlag < Mongoid::Migration
    def self.up
      FeatureFlag.retire_feature_flag('explore_tab_default')
    end

    def self.down
      FeatureFlag.create!(name: 'explore_tab_default',
                          default_value: false,
                          description: 'show the explore tab in study overview by default')
    end
  end
