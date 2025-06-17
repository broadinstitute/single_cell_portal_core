# frozen_string_literal: true

# service that handles preprocessing expression/annotation data to speed up dot plot rendering
class DotPlotService
  # main handler for launching ingest job to process expression data
  #
  # * *params*
  #   - +study+ (Study) => the study that owns the data
  #   - +cluster_group+ (ClusterGroup) => the cluster to source cell names from
  #   - +annotation_file+ (StudyFile) => the StudyFile containing annotation data
  #   - +expression_file+ (StudyFile) => the StudyFile to source data from
  #
  # * *yields*
  #   - (IngestJob) => the job that will be run to process the data
  def self.run_preprocess_expression_job(study, cluster_group, annotation_file, expression_file)
    study_eligible?(study) # method stub, waiting for scp-ingest-pipeline implementation
  end

  # determine study eligibility - can only have one processed matrix and be able to visualize clusters
  #
  # * *params*
  #   - +study+ (Study) the study that owns the data
  # * *returns*
  #   - (Boolean) true if the study is eligible for dot plot visualization
  def self.study_eligible?(study)
    processed_matrices = study_processed_matrices(study)
    study.can_visualize_clusters? && study.has_expression_data? && processed_matrices.size == 1
  end

  # check if the given study/cluster has already been preprocessed
  # * *params*
  #   - +study+ (Study) the study that owns the data
  #   - +cluster_group+ (ClusterGroup) the cluster to check for processed data
  #
  # * *returns*
  #   - (Boolean) true if the study/cluster has already been processed
  def self.cluster_processed?(study, cluster_group)
    DotPlotGene.where(study:, cluster_group:).exists?
  end

  # get processed expression matrices for a study
  #
  # * *params*
  #   - +study+ (Study) the study to get matrices for
  #
  # * *returns*
  #   - (Array<StudyFile>) an array of processed expression matrices for the study
  def self.study_processed_matrices(study)
    study.expression_matrices.select do |matrix|
      matrix.is_viz_anndata? || !matrix.is_raw_counts_file?
    end
  end

  # seeding method for testing purposes, will be removed once pipeline is in place
  # data is random and not representative of actual expression data
  def self.seed_dot_plot_genes(study)
    return false unless study_eligible?(study)

    DotPlotGene.where(study_id: study.id).delete_all
    puts "Seeding dot plot genes for #{study.accession}"
    expression_matrix = study.expression_matrices.first
    print 'assembling genes and annotations...'
    genes = Gene.where(study:, study_file: expression_matrix).pluck(:name)
    annotations = AnnotationVizService.available_metadata_annotations(
      study, annotation_type: 'group'
    ).reject { |a| a[:scope] == 'invalid' }
    puts " done. Found #{genes.size} genes and #{annotations.size} study-wide annotations."
    study.cluster_groups.each do |cluster_group|
      next if cluster_processed?(study, cluster_group)

      cluster_annotations = ClusterVizService.available_annotations_by_cluster(
        cluster_group, 'group'
      ).reject { |a| a[:scope] == 'invalid' }
      all_annotations = annotations + cluster_annotations
      puts "Processing #{cluster_group.name} with #{all_annotations.size} annotations."
      documents = []
      genes.each do |gene|
        exp_scores = all_annotations.map do |annotation|
          {
            "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}" => annotation[:values].map do |value|
              { value => [rand.round(3), rand.round(3)] }
            end.reduce({}, :merge)
          }
        end.reduce({}, :merge)
        documents << DotPlotGene.new(
          study:, study_file: expression_matrix, cluster_group:, gene_symbol: gene, searchable_gene: gene.downcase,
          exp_scores:
        ).attributes
        if documents.size == 1000
          DotPlotGene.collection.insert_many(documents)
          count = DotPlotGene.where(study_id: study.id, cluster_group_id: cluster_group.id).size
          puts "Inserted #{count}/#{genes.size} DotPlotGenes for #{cluster_group.name}."
          documents.clear
        end
      end
      DotPlotGene.collection.insert_many(documents)
      count = DotPlotGene.where(study_id: study.id, cluster_group_id: cluster_group.id).size
      puts "Inserted #{count}/#{genes.size} DotPlotGenes for #{cluster_group.name}."
      puts "Finished processing #{cluster_group.name}"
    end
    puts "Seeding complete for #{study.accession}, #{DotPlotGene.where(study_id: study.id).size} DotPlotGenes created."
    true
  rescue StandardError => e
    puts "Error seeding DotPlotGenes in #{study.accession}: #{e.message}"
    false
  end
end
