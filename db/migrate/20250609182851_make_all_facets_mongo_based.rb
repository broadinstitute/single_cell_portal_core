class MakeAllFacetsMongoBased < Mongoid::Migration
  def self.up
    SearchFacet.update_all(is_mongo_based: true)
    CellMetadatum.where(name: 'organism_age').map(&:set_minmax_by_units!)
  end

  def self.down
    SearchFacet.where(is_presence_facet: false).update_all(is_mongo_based: true)
  end
end
