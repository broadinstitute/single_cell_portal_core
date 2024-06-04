class AddBrainModalityColumnsToBigQuery < Mongoid::Migration
  # note this operation is safe to run even if your BQ table already has the given column
  def self.up
    columns = %w[has_morphology has_electrophysiology]
    client = BigQueryClient.new.client
    [CellMetadatum::BIGQUERY_DATASET, 'cell_metadata_test'].each do |dataset_name|
      dataset = client.dataset(dataset_name)
      if dataset.present? # ensure test dataset exists to avoid migration failure
        table = dataset.table(CellMetadatum::BIGQUERY_TABLE)
        columns.each do |column_name|
          table.schema {|s| s.boolean(column_name, mode: :nullable)}
        end
      end
    end
  end

  def self.down
    # BigQuery does not support column deletions except by dropping and recreating the table,
    # so we'll cross that bridge when/if we come to it
    # See https://cloud.google.com/bigquery/docs/manually-changing-schemas
  end
end
