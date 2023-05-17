class AddFlagForExploreTabUxUpdates < Mongoid::Migration
  def self.up
    FeatureFlag.create!(name: 'show_explore_tab_ux_updates',
                        default_value: false,
                        description: 'show the "Update the Explore Tab" epic changes')
  end

  def self.down
    FeatureFlag.find_by(name: 'show_explore_tab_ux_updates')&.destroy
  end
end
