# handles launching ingest jobs for AnnData files and derived SCP file fragments
# see IngestJob#launch_anndata_subparse_jobs for usage patterns
class AnnDataIngestParameters
  include ActiveModel::Model
  include Parameterizable

  # default values for parameters, also used as control list for attributes hash
  # attributes marked as true are passed to the command line as a standalone flag with no value
  # e.g. --ingest-anndata
  # any parameters that are set to nil/false will not be passed to the command line
  #
  # DEFINITIONS
  # ingest_anndata: gate primary validation/extraction of AnnData file
  # anndata_file: GS URL for AnnData file
  # extract: array of values for different file type extractions
  # obsm_keys: data slots containing clustering information
  # ingest_cluster: gate ingesting an extracted cluster file
  # cluster_file: GS URL for extracted cluster file
  # name: name of ClusterGroup (from obsm_keys)
  # domain_ranges: domain ranges for ClusterGroup, if present
  # cell_metadata_file: GS URL for extracted metadata file
  # ingest_cell_metadata: gate ingesting an extracted metadata file
  # ingest_expression: gate ingesting an extracted MTX file
  # matrix_file: GS URL of extracted MTX file
  # matrix_file_type: type of matrix file (should always be 'mtx' when used with :ingest_expression)
  # gene_file: GS URL of extracted 10X features file
  # barcode_file: GS URL of extracted 10X barcodes file
  PARAM_DEFAULTS = {
    ingest_anndata: true,
    anndata_file: nil,
    obsm_keys: %w[X_umap X_tsne],
    ingest_cluster: false,
    cluster_file: nil,
    name: nil,
    domain_ranges: nil,
    extract: %w[cluster metadata processed_expression],
    cell_metadata_file: nil,
    ingest_cell_metadata: false,
    study_accession: nil,
    ingest_expression: false,
    matrix_file: nil,
    matrix_file_type: nil,
    gene_file: nil,
    barcode_file: nil
  }.freeze

  attr_accessor(*PARAM_DEFAULTS.keys)

  validates :anndata_file, :cluster_file, :cell_metadata_file, :matrix_file, :gene_file, :barcode_file,
            format: { with: Parameterizable::GS_URL_REGEXP, message: 'is not a valid GS url' },
            allow_blank: true
end
