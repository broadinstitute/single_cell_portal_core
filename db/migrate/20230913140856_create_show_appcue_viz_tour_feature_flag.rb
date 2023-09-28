class CreateShowAppcueVizTourFeatureFlag < Mongoid::Migration
  def self.up
    FeatureFlag.create!(name: 'show_appcue_viz_tour',
                        default_value: false,
                        description: "show the 'Take a tour of SCP's visualization tools' Appcue")
  end

  def self.down
    FeatureFlag.retire_feature_flag('show_appcue_viz_tour')
  end
end
