class MakeAllFacetsMongoBased < Mongoid::Migration
  def self.up
    SearchFacet.update_all(is_mongo_based: true)
    # Only process CellMetadatum records that have a valid study association
    CellMetadatum.where(name: 'organism_age').each do |cell_metadatum|
      next if cell_metadatum.study.nil?
      cell_metadatum.set_minmax_by_units!
    end
  end

  def self.down
    SearchFacet.where(is_presence_facet: false).update_all(is_mongo_based: true)
  end
end
