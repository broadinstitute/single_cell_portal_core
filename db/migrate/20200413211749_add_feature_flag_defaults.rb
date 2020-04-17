



class AddFeatureFlagDefaults < Mongoid::Migration
  # mirror of FeatureFlag.rb, so this migration won't error if that class is renamed/altered
  class FeatureFlagMigrator
    include Mongoid::Document
    store_in collection: 'feature_flags'
    field :name, type: String
    field :default_value, type: Boolean, default: false
    field :description, type: String
  end

  def self.up
    FeatureFlagMigrator.create!(name: 'advanced_search',
                        default_value: false,
                        description: 'whether to show the React-powered, ajax search UI')

    FeatureFlagMigrator.create!(name: 'faceted_search',
                        default_value: false,
                        description: 'whether to show the facet controls in the advanced search')

    FeatureFlagMigrator.create!(name: 'covid19_page',
                        default_value: false,
                        description: 'whether to show the COVID-19 link on the homepage')
  end

  def self.down
    FeatureFlagMigrator.destroy_all
  end
end
