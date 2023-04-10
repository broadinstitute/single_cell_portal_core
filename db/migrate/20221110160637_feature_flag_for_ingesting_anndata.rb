class FeatureFlagForIngestingAnndata < Mongoid::Migration
    # mirror of FeatureFlag.rb, so this migration won't error if that class is renamed/altered
    class FeatureFlagMigrator
      include Mongoid::Document
      store_in collection: 'feature_flags'
      field :name, type: String
      field :default_value, type: Boolean, default: false
      field :description, type: String
    end
  
    def self.up
      FeatureFlagMigrator.create!(name: 'ingest_anndata_file',
                                  default_value: false,
                                  description: 'allow AnnData files to ingest or not')
    end
  
    def self.down
      FeatureFlagMigrator.find_by(name: 'ingest_anndata_file').destroy
    end
  end
  