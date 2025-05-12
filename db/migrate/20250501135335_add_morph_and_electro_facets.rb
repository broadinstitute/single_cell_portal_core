class AddMorphAndElectroFacets < Mongoid::Migration
  @names = %w[has_morphology has_electrophysiology]
  @columns = %w[bil_url dandi_url]
  @new_facets = @names.zip(@columns).to_h
  def self.up
    @new_facets.each do |identifier, column|
      SearchFacet.create!(
        name: identifier.humanize, identifier:, big_query_id_column: column, big_query_name_column: column,
        is_mongo_based: true, is_presence_facet: true, convention_name: 'alexandria_convention', data_type: 'string',
        convention_version: '3.0.0', visible: true
      )
    end
  end

  def self.down
    SearchFacet.where(:identifier.in => @names).delete_all
  end
end
