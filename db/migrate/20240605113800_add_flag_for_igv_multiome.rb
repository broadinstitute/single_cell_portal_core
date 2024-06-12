class AddFlagForIgvMultiome < Mongoid::Migration
  def self.up
    FeatureFlag.create!(name: 'show_igv_multiome',
                        default_value: false,
                        description: 'show features related to IGV multiome')
  end

  def self.down
    FeatureFlag.find_by(name: 'show_igv_multiome')&.destroy
  end
end
