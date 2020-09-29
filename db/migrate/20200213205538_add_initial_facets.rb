class AddInitialFacets < Mongoid::Migration
  def self.up
    SearchFacetPopulator.populate_from_schema
  end

  def self.down
    SearchFacet.destroy_all
  end
end
