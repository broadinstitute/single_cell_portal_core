# handles launching ingest jobs for AnnData files and derived SCP file fragments
# usage patterns:
# extract SCP files: AnnDataIngestParameters.new(anndata_file: study_file.gs_url)
# parse extracted cluster file: AnnDataIngestParameters.new(
#   ingest_anndata: false, extract_cluster: false, name: 'X_tsne', ingest_cluster: true, domain_ranges: "{}"
#   cluster_file: 'gs://bucket-id/X_tsne.cluster.anndata_segment.tsv', obsm_keys: nil
# )
class AnnDataIngestParameters
  include ActiveModel::Model
  include Parameterizable

  # ingest_anndata: gate primary validation/extraction of AnnData file
  # anndata_file: GS URL for AnnData file
  # extract_cluster: gate cluster file extraction
  # obsm_keys: data slots containing clustering information
  # ingest_cluster: gate ingesting an extracted cluster file
  # cluster_file: GS URL for extracted cluster file
  # name: name of ClusterGroup (from obsm_keys)
  # domain_ranges: domain ranges for ClusterGroup, if present
  attr_accessor :ingest_anndata, :anndata_file, :extract_cluster, :obsm_keys, :ingest_cluster, :cluster_file, :name,
                :domain_ranges

  validates :anndata_file, :cluster_file,
            format: { with: Parameterizable::GS_URL_REGEXP, message: 'is not a valid GS url' },
            allow_blank: true

  # default values for parameters
  # attributes marked as true are passed to the command line as a standalone flag with no value, e.g. --extract-cluster
  # any parameters that are set to nil/false will not be passed to the command line
  PARAM_DEFAULTS = {
    ingest_anndata: true,
    extract_cluster: true,
    obsm_keys: "['X_umap','X_tsne']",
    ingest_cluster: false,
    cluster_file: nil,
    name: nil,
    domain_ranges: nil
  }.freeze

  ARRAY_MATCHER = /[\[\]]/
  QUOTE_MATCHER = /["']/

  def initialize(attributes = {})
    PARAM_DEFAULTS.each do |attribute_name, default|
      send("#{attribute_name}=", default) if default.present?
    end
    super
  end

  def attributes
    {
      ingest_anndata:, anndata_file:, extract_cluster:, obsm_keys:, ingest_cluster:, cluster_file:, name:, domain_ranges:
    }.with_indifferent_access
  end

  # generate a GS URL to a derived fragment that was extracted from the parent AnnData file
  def fragment_file_gs_url(bucket_id, fragment_type, name)
    "gs://#{bucket_id}/_scp_internal/anndata_ingest/#{name}.#{fragment_type}.anndata_segment.tsv"
  end

  # convert a string value into an array of strings, like obsm_keys
  def attribute_as_array(attr)
    stripped_value = attributes[attr].gsub(ARRAY_MATCHER, '')
    stripped_value.split(',').map { |substr| substr.gsub(QUOTE_MATCHER, '').strip }
  end
end
