class UpdateFacetLinks < Mongoid::Migration
  def self.up
    SearchFacetPopulator.populate_from_schema
  end

  def self.down
  end
end
