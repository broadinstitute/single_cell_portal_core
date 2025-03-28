class AddRawCountsRequiredBackendFeatureFlag < Mongoid::Migration
  # mirror of FeatureFlag.rb, so this migration won't error if that class is renamed/altered
  class FeatureFlagMigrator
    include Mongoid::Document
    store_in collection: 'feature_flags'
    field :name, type: String
    field :default_value, type: Boolean, default: false
    field :description, type: String
  end

  def self.up
    FeatureFlagMigrator.create!(name: 'raw_counts_required_backend',
                                default_value: false,
                                description: 'require users to add raw expression matrices ahead of processed matrices')
  end

  def self.down
    FeatureFlagMigrator.find_by(name: 'raw_counts_required_backend').destroy
  end
end
