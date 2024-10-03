# store pointers to differential expression output sets for a given cluster/annotation
class DifferentialExpressionResult
  include Mongoid::Document
  include Mongoid::Timestamps
  include Annotatable # handles getting/setting annotation objects

  # minimum number of one_vs_rest_comparisons, or cells per observed_value
  MIN_OBSERVED_VALUES = 2

  # supported computational methods for differential expression results in Scanpy
  # from https://scanpy.readthedocs.io/en/stable/generated/scanpy.tl.rank_genes_groups.html
  DEFAULT_COMP_METHOD = 'wilcoxon'.freeze
  SUPPORTED_COMP_METHODS = [
    DEFAULT_COMP_METHOD, 'logreg', 't-test', 't-test_overestim_var', 'custom'
  ].freeze

  belongs_to :study
  belongs_to :cluster_group
  belongs_to :study_file, optional: true

  field :cluster_name, type: String # cache name of cluster at time of creation to avoid renaming issues
  field :one_vs_rest_comparisons, type: Array, default: []
  # hash of any pairwise comparisons representing possible combinations of labels (may not be exhaustive)
  # e.g. { A: [B, C, D], B: [C, D], C: [D] }
  field :pairwise_comparisons, type: Hash, default: {}
  field :annotation_name, type: String
  field :annotation_scope, type: String
  field :computational_method, type: String, default: DEFAULT_COMP_METHOD
  field :matrix_file_id, type: BSON::ObjectId # associated raw count matrix study file
  field :is_author_de, type: Boolean, default: false

  # Fields for author DE
  field :gene_header, type: String
  field :group_header, type: String
  field :comparison_group_header, type: String
  field :size_metric, type: String
  field :significance_metric, type: String


  validates :annotation_scope, inclusion: { in: %w[study cluster] }
  validates :cluster_name, presence: true
  validates :matrix_file_id, presence: true, unless: proc { study_file.present? }
  validates :computational_method, presence: true
  validates :annotation_name, presence: true, uniqueness: { scope: %i[study cluster_group annotation_scope] }
  validate :comparisons_available?
  validate :matrix_file_exists?
  validate :annotation_exists?

  before_validation :set_cluster_name
  before_validation :set_one_vs_rest_comparisons, unless: proc { study_file.present? }
  before_destroy :remove_output_files

  ## STUDY FILE GETTERS
  # associated raw count matrix
  def matrix_file
    # use find_by(id:) to avoid Mongoid::Errors::InvalidFind
    StudyFile.find_by(id: matrix_file_id)
  end

  # name of associated matrix file
  def matrix_file_name
    matrix_file&.upload_file_name
  end

  # associated clustering file
  def cluster_file
    cluster_group.study_file
  end

  # associated annotation file
  def annotation_file
    case annotation_scope
    when 'study'
      study.metadata_file
    when 'cluster'
      cluster_file
    end
  end

  # compute the relative path inside a GCS bucket of a DE output file for a given label/comparison
  def bucket_path_for(label, comparison_group: nil)
    "_scp_internal/differential_expression/#{filename_for(label, comparison_group:)}"
  end

  # individual filename of one-vs-rest comparison or pairwise comparison
  # will convert non-word characters to underscores "_", except plus signs "+" which are changed to "pos"
  # this is to handle cases where + or - are the only difference in labels, such as CD4+ and CD4-
  def filename_for(label, comparison_group: nil)
    if comparison_group.present?
      first_label, second_label = Naturally.sort([label, comparison_group]) # comparisons must be sorted
      values = [cluster_name, annotation_name, first_label, second_label, annotation_scope, computational_method]
    else
      values = [cluster_name, annotation_name, label, annotation_scope, computational_method]
    end
    basename = DifferentialExpressionService.encode_filename(values)
    "#{basename}.tsv"
  end

  # path to auto-generate manifest for author-uploaded DE files
  def manifest_bucket_path
    manifest_basename = DifferentialExpressionService.encode_filename(
      [cluster_name, annotation_name, 'manifest']
    )
    "_scp_internal/differential_expression/#{manifest_basename}.tsv"
  end

  # get all output files for a comparison type, e.g. one-vs-rest or pairwise
  #
  # * *params*
  #   - +comparison_type+ (String, Symbol) => :one_vs_rest or :pairwise comparisons
  #   - +transform+ (Symbol) => method to apply to filename (:filename_for or :bucket_path_for)
  #   - +include_labels+ (Boolean) => T/F to prepend observation labels (including pairwise comparison)
  #
  # * *returns*
  #   - (Array<String>)
  def files_for(comparison_type, transform: :filename_for, include_labels: false)
    case comparison_type.to_sym
    when :one_vs_rest
      one_vs_rest_comparisons.map do |label|
        filename = send(transform, label)
        include_labels ? [label, filename] : filename
      end
    when :pairwise
      pairwise_files = []
      pairwise_comparisons.each_pair do |group, comparison_groups|
        comparison_groups.each do |comparison_group|
          filename = send(transform, group, comparison_group:)
          result = include_labels ? [group, comparison_group, filename] : filename
          pairwise_files << result
        end
      end
      pairwise_files
    else
      []
    end
  end

  # map listing all result files and their constituent groups , by comparison type
  # this is important as it sidesteps the issue of study owners renaming clusters, as cluster_name is cached here
  #
  # @return [Hash<String => Array<String, String>, Array<String, String, String>]
  def result_files
    {
      is_author_de:,
      headers: {
        gene: gene_header,
        group: group_header,
        comparison_group: comparison_group_header,
        size: size_metric,
        significance: significance_metric
      },
      one_vs_rest: files_for(:one_vs_rest, include_labels: true),
      pairwise: files_for(:pairwise, include_labels: true)
    }.with_indifferent_access
  end

  # array of all result files paths relative to associated bucket root for one-vs-rest & pairwise
  def bucket_files
    %i[one_vs_rest pairwise].map do |comparison_type|
      files_for(comparison_type, transform: :bucket_path_for)
    end.flatten
  end

  # number of different pairwise comparisons
  # e.g. { a: [b,c] } => 2 comparisons (a:b, a:c)
  #      { a: [b,c], b: [c] } => 3 comparisons (a:b, a:c, b:c)
  def num_pairwise_comparisons
    pairwise_comparisons.values.map(&:count).reduce(0, &:+)
  end

  # initialize one-vs-rest and pairwise comparisons from manifest contents
  # will clobber any previous values and save in place once completed, so only use with new instances
  #
  # * *params*
  #   -+comparisons+ (Array<Array<String>>) => Array of arrays of strings, only 1 or 2 entries in each
  def initialize_comparisons!(comparisons)
    comparisons.each do |groups|
      if groups.size == 1
        one_vs_rest_comparisons << groups.first.strip
      else
        group, comparison_group = groups.map(&:strip)
        pairwise_comparisons[group] ||= []
        pairwise_comparisons[group] << comparison_group unless pairwise_comparisons[group].include?(comparison_group)
      end
    end
    save!
  end

  private

  # find the intersection of annotation values from the source, filtered for cells observed in cluster
  def set_one_vs_rest_comparisons
    cells_by_label = ClusterVizService.cells_by_annotation_label(cluster_group,
                                                                 annotation_name,
                                                                 annotation_scope)
    observed = cells_by_label.keys.reject { |label| cells_by_label[label].count < MIN_OBSERVED_VALUES }
    self.one_vs_rest_comparisons = observed
  end

  def set_cluster_name
    self.cluster_name = cluster_group.name
  end

  def comparisons_available?
    if one_vs_rest_comparisons.empty? && pairwise_comparisons.empty?
      errors.add(:base, 'result is missing both one_vs_rest_comparisons and pairwise_comparisons')
    elsif one_vs_rest_comparisons.count < MIN_OBSERVED_VALUES && pairwise_comparisons.empty?
      errors.add(:one_vs_rest_comparisons,
                 "must have at least #{MIN_OBSERVED_VALUES} values without pairwise_comparisons specified")
    end
  end

  # validate we have a matrix file that was used to compute results (unless this is sourced from a user-uploaded file)
  def matrix_file_exists?
    study_file.present? ? true : matrix_file.present?
  end

  def annotation_exists?
    if annotation_object.blank?
      errors.add(:base, "Annotation: #{annotation_name} (#{annotation_scope}) not found")
    end
  end

  # delete all associated output files on destroy
  def remove_output_files
    # prevent failures when bucket doesn't exist, or if this is running in a cleanup job after a study is destroyed
    # these are mostly for protection in CI when calling study.destroy_and_remove_workspace
    # in production, DeleteQueueJob will handle all necessary cleanup
    return true if study.nil? || study.detached || study.queued_for_deletion

    identifier = "#{study.accession}:#{annotation_name}--group--#{annotation_scope}"
    bucket_files.each do |filepath|
      remote = ApplicationController.firecloud_client.get_workspace_file(study.bucket_id, filepath)
      if remote.present?
        Rails.logger.info "Removing DE output #{identifier} at #{filepath}"
        remote.delete
      end
    end

    if is_author_de
      filepath = manifest_bucket_path
      remote = ApplicationController.firecloud_client.get_workspace_file(study.bucket_id, filepath)
      Rails.logger.info "Removing manifest for #{identifier} at #{filepath}"
      remote.delete if remote.present?
    end
  end
end
