class CreateOrganismAgeFacetAndBackfillData < Mongoid::Migration
  def self.up
    # SearchFacet.where(identifier: 'organism_age').destroy
    # bq_dataset = SearchFacet.big_query_dataset
    # update_command = "UPDATE #{CellMetadatum::BIGQUERY_TABLE} "
    # update_command += "SET organism_age__seconds = CAST((organism_age * #{SearchFacet::TIME_MULTIPLIERS['years']}) AS NUMERIC) "
    # update_command += "WHERE organism_age IS NOT NULL and organism_age__seconds IS NULL AND organism_age__unit_label = 'year'"
    # bq_dataset.query update_command
    # SearchFacet.create(name: 'Organism Age', identifier: 'organism_age', big_query_id_column: 'organism_age',
    #                    big_query_name_column: 'organism_age', big_query_conversion_column: 'organism_age__seconds',
    #                    is_ontology_based: false, data_type: 'number', is_array_based: false,
    #                    convention_name: 'Alexandria Metadata Convention', convention_version: '1.1.3', unit: 'years')
  end

  def self.down
    # SearchFacet.where(identifier: 'organism_age').destroy
    # bq_dataset = SearchFacet.big_query_dataset
    # update_command = "UPDATE #{CellMetadatum::BIGQUERY_TABLE} SET organism_age__seconds = NULL WHERE organism_age IS NOT NULL"
    # bq_dataset.query update_command
  end
end
