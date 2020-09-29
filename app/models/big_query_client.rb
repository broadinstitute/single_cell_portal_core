##
# BigQueryClient: lightweight shim around Google::Cloud::BigQuery library to DRY up references to credentials/datasets

class BigQueryClient < Struct.new(:project, :service_account_credentials, :client)

  # GCP Compute project to run reads/writes in
  COMPUTE_PROJECT = ENV['GOOGLE_CLOUD_PROJECT'].blank? ? '' : ENV['GOOGLE_CLOUD_PROJECT']
  # Service account JSON credentials
  SERVICE_ACCOUNT_KEY = !ENV['SERVICE_ACCOUNT_KEY'].blank? ? File.absolute_path(ENV['SERVICE_ACCOUNT_KEY']) : ''

  def initialize
    Google::Cloud::Bigquery.configure do |config|
      config.project_id  = COMPUTE_PROJECT
      config.credentials = SERVICE_ACCOUNT_KEY
      config.timeout = 120
    end
    self.project = COMPUTE_PROJECT
    self.service_account_credentials = SERVICE_ACCOUNT_KEY
    self.client = Google::Cloud::Bigquery.new
  end

  # clears the entire BQ table.  This is only intended for utility use in tests/development
  # it will no-op in production
  def self.clear_bq_table
    if Rails.env.production?
      return
    end
    client = BigQueryClient.new.client
    query = "DELETE FROM #{CellMetadatum::BIGQUERY_TABLE} WHERE 1 = 1"
    client.dataset(CellMetadatum::BIGQUERY_DATASET).query(query)
  end
end
