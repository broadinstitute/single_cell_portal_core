class RetireAppcuePinFeatureFlag < Mongoid::Migration
  def self.up
    FeatureFlag.retire_feature_flag('show_appcue_viz_tour')
  end

  def self.down
    FeatureFlag.create!(name: 'show_appcue_viz_tour',
                        default_value: false,
                        description: "show the 'Take a tour of SCP's visualization tools' Appcue")
  end
end
