class AddCellTypeCustomFacet < Mongoid::Migration
  def self.up
    # remove existing facet if it already exists due to testing
    SearchFacet.find_by(identifier: 'cell_type__custom')&.destroy
    SearchFacet.create(
      identifier: 'cell_type__custom',
      name: 'cell type (custom)',
      data_type: 'string',
      big_query_id_column: 'cell_type__custom',
      big_query_name_column: 'cell_type__custom',
      convention_version: '2.1.1',
      convention_name: 'alexandria_convention',
      is_array_based: false,
      visible: true
    )
  end

  def self.down
    SearchFacet.find_by(identifier: 'cell_type__custom')&.destroy
  end
end
