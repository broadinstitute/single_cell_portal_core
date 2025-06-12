class AddBiosampleTypeAndPreservationMethodToBq < Mongoid::Migration
  def self.up
    # client = BigQueryClient.new.client
    # [CellMetadatum::BIGQUERY_DATASET, 'cell_metadata_test'].each do |dataset_name|
    #   dataset = client.dataset(dataset_name)
    #   if dataset.present? # ensure test dataset exists to avoid migration failure
    #     table = dataset.table(CellMetadatum::BIGQUERY_TABLE)
    #     table.schema {|s| s.string('biosample_type', mode: :nullable)}
    #     table.schema {|s| s.string('preservation_method', mode: :nullable)}
    #   end
    # end
  end

  def self.down
  end
end
