class AddFeatureFlagForExploreTabAbTest < Mongoid::Migration
  def self.up
    FeatureFlag.create!(name: 'explore_tab_default',
                        default_value: false,
                        description: 'show the explore tab in study overview by default')
  end

  def self.down
    FeatureFlag.find_by(name: 'explore_tab_default')&.destroy
  end
end
