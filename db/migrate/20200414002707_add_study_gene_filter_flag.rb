class AddStudyGeneFilterFlag < Mongoid::Migration
  class FeatureFlagMigrator
    include Mongoid::Document
    store_in collection: 'feature_flags'
    field :name, type: String
    field :default_value, type: Boolean, default: false
    field :description, type: String
  end
  def self.up
    FeatureFlagMigrator.create!(name: 'gene_study_filter',
                                default_value: false,
                                description: 'whether global gene search can be narrowed by a study filter')
  end

  def self.down
    FeatureFlagMigrator.find_by(name: 'gene_study_filter').destroy
  end
end
