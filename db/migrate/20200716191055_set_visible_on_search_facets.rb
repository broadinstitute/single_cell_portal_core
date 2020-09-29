class SetVisibleOnSearchFacets < Mongoid::Migration
  def self.up
    SearchFacet.update_all(visible: true)
  end

  def self.down
  end
end
