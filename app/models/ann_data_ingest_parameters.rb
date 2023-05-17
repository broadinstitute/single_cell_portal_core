# handles launching ingest jobs for AnnData files and derived SCP file fragments
# usage patterns:
# extract SCP files: AnnDataIngestParameters.new(anndata_file: study_file.gs_url)
# parse extracted cluster file: AnnDataIngestParameters.new(
#   ingest_anndata: false, extract: nil, name: 'X_tsne', ingest_cluster: true, domain_ranges: "{}",
#   cluster_file: 'gs://bucket-id/_scp_internal/anndata_ingest/<study_file_ID_of_h5ad_file>/h5ad_frag.cluster.X_tsne.tsv',
#   obsm_keys: %w[X_tsne]
# )
# parse extracted metadata file: AnnDataIngestParameters.new(
#   ingest_anndata: false, extract: nil, name: 'X_tsne', ingest_cluster: false, domain_ranges: nil
#   cluster_file: nil, obsm_keys: nil, cell_metadata_file: 'gs://bucket-id/_scp_internal/anndata_ingest/<study_file_ID_of_h5ad_file>/h5ad_frag.metadata.tsv',
#   ingest_cell_metadata: true, study_accession: SCP111
# )

class AnnDataIngestParameters
  include ActiveModel::Model
  include Parameterizable

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
  attr_accessor :ingest_anndata, :anndata_file, :extract, :obsm_keys, :ingest_cluster, :cluster_file, :name,
                :domain_ranges, :cell_metadata_file, :ingest_cell_metadata, :study_accession

  validates :anndata_file, :cluster_file, :cell_metadata_file,
            format: { with: Parameterizable::GS_URL_REGEXP, message: 'is not a valid GS url' },
            allow_blank: true

  # default values for parameters
  # attributes marked as true are passed to the command line as a standalone flag with no value
  # e.g. --extract "['cluster', 'metadata']"
  # any parameters that are set to nil/false will not be passed to the command line
  PARAM_DEFAULTS = {
    ingest_anndata: true,
    obsm_keys: %w[X_umap X_tsne],
    ingest_cluster: false,
    cluster_file: nil,
    name: nil,
    domain_ranges: nil,
    extract: %w[cluster metadata processed_expression],
    cell_metadata_file: nil,
    ingest_cell_metadata: false,
    study_accession: nil
  }.freeze

  def initialize(attributes = {})
    PARAM_DEFAULTS.each do |attribute_name, default|
      send("#{attribute_name}=", default) if default.present?
    end
    super
  end

  def attributes
    {
      ingest_anndata:, anndata_file:, extract:, obsm_keys:, ingest_cluster:, cluster_file:,
      name:, domain_ranges:, cell_metadata_file:, ingest_cell_metadata:, study_accession:
    }.with_indifferent_access
  end

  # generate a GS URL to a derived fragment that was extracted from the parent AnnData file
  # File name structure is: <input_filetype>_frag.<file_type>.<file_type_detail>.tsv
  #   file_type = cluster|metadata|matrix
  #   file_type_detail [optional] = cluster name (for cluster files), raw|processed (for matrix files)
  def fragment_file_url(bucket_id, fragment_type, h5ad_file_id, file_type_detail = "")
    url = "gs://#{bucket_id}/_scp_internal/anndata_ingest/#{h5ad_file_id}/h5ad_frag.#{fragment_type}"
    if file_type_detail.present?
      url += ".#{file_type_detail}.tsv"
    else
      url += ".tsv"
    end
    url
  end
end
