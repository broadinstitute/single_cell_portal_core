class AddMetadataConventionVersionToBq < Mongoid::Migration
  def self.up
    # do portal table first, then test dataset
    # client = BigQueryClient.new.client
    # [CellMetadatum::BIGQUERY_DATASET, 'cell_metadata_test'].each do |dataset_name|
    #   dataset = client.dataset(dataset_name)
    #   if dataset.present? # ensure test dataset exists to avoid migration failure
    #     table = dataset.table(CellMetadatum::BIGQUERY_TABLE)
    #     table.schema {|s| s.string('metadata_convention_version', mode: :nullable)}
    #     update_command = "UPDATE #{CellMetadatum::BIGQUERY_TABLE} "
    #     update_command += "SET metadata_convention_version = '1.1.3'"
    #     update_command += "WHERE metadata_convention_version IS NULL"
    #     dataset.query update_command
    #   end
    # end
  end

  def self.down
    # client = BigQueryClient.new.client
    # [CellMetadatum::BIGQUERY_DATASET, 'cell_metadata_test'].each do |dataset_name|
    #   dataset = client.dataset(dataset_name)
    #   if dataset.present? # ensure test dataset exists to avoid migration failure
    #     update_command = "UPDATE #{CellMetadatum::BIGQUERY_TABLE} "
    #     update_command += "SET metadata_convention_version = NULL"
    #     update_command += "WHERE metadata_convention_version = '1.1.3'"
    #     dataset.query update_command
    #   end
    # end
  end
end
