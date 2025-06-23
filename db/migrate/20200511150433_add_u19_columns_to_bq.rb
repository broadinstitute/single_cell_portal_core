class AddU19ColumnsToBq < Mongoid::Migration
  def self.up
    # client = BigQueryClient.new.client
    # [CellMetadatum::BIGQUERY_DATASET, 'cell_metadata_test'].each do |dataset_name|
    #   dataset = client.dataset(dataset_name)
    #   if dataset.present? # ensure test dataset exists to avoid migration failure
    #     table = dataset.table(CellMetadatum::BIGQUERY_TABLE)
    #     table.schema {|s| s.string('organ_region', mode: :repeated)}
    #     table.schema {|s| s.string('organ_region__ontology_label', mode: :repeated)}
    #     table.schema {|s| s.string('cell_type__custom', mode: :nullable)}
    #   end
    # end
  end

  def self.down
  end
end
