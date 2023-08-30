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
    matrix_file: nil,
    matrix_file_type: nil,
    gene_file: nil,
    barcode_file: nil,
    subsample: false,
    file_size: 0
  }.freeze

  # values that are available as methods but not as attributes (and not passed to command line)
  NON_ATTRIBUTE_PARAMS = %i[file_size].freeze

  # GCE machine types and file size ranges for handling fragment extraction
  # produces a hash with entries like { 'n2-highmem-4' => 0..4.gigabytes }
  EXTRACT_MACHINE_TYPES = [4, 8, 16, 32].map.with_index do |cores, index|
    floor = index == 0 ? 0 : (cores / 2).gigabytes
    limit = (cores * 8).gigabytes
    # ranges that use '...' exclude the given end value.
    { "n2d-highmem-#{cores}" => floor...limit }
  end.reduce({}, :merge)

  attr_accessor(*PARAM_DEFAULTS.keys)

  validates :anndata_file, :cluster_file, :cell_metadata_file, :matrix_file, :gene_file, :barcode_file,
            format: { with: Parameterizable::GS_URL_REGEXP, message: 'is not a valid GS url' },
            allow_blank: true

  # determine which GCE machine type to use for fragment extraction based on file size
  # see https://ruby-doc.org/core-3.1.0/Range.html#method-i-3D-3D-3D for range detection doc
  def machine_type
    EXTRACT_MACHINE_TYPES.detect { |_, mem_range| mem_range === file_size }&.first || 'n2d-highmem-4'
  end
end
