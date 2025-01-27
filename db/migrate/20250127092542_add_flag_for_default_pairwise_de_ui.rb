class AddFlagForDefaultPairwiseDeUi < Mongoid::Migration
  def self.up
    FeatureFlag.create!(name: 'default_pairwise_de_ui',
                        default_value: false,
                        description: 'show pairwise differential expression UI by default')
  end

  def self.down
    FeatureFlag.find_by(name: 'default_pairwise_de_ui')&.destroy
  end
end
