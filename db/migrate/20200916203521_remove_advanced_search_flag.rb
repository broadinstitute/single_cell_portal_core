class RemoveAdvancedSearchFlag < Mongoid::Migration
  FLAG_NAME = 'advanced_search'

   # mirror of FeatureFlag.rb, so this migration won't error if that class is renamed/altered
  class FeatureFlagMigrator
    include Mongoid::Document
    store_in collection: 'feature_flags'
    field :name, type: String
    field :default_value, type: Boolean, default: false
    field :description, type: String
  end

  def self.up
    FeatureFlagMigrator.where(name: FLAG_NAME).destroy_all
    [User, BrandingGroup].each do |model|
      FeatureFlaggable.remove_flag_from_model(model, FLAG_NAME)
    end
  end

  def self.down
    FeatureFlagMigrator.create!(name: FLAG_NAME,
                                default_value: false,
                                description: 'whether to show the React-powered, ajax search UI')
  end
end
