require 'test_helper'

class DotPlotGeneTest < ActiveSupport::TestCase
  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'DotPlotGene Test Study',
                               user: @user,
                               test_array: @@studies_to_clean)
    @cluster_file = FactoryBot.create(:cluster_file, name: 'cluster_example.txt', study: @study)
    @expression_file = FactoryBot.create(:expression_file, name: 'expression_example.txt', study: @study)
    @metadata_file = FactoryBot.create(:metadata_file,
                                       name: 'metadata.txt',
                                       study: @study,
                                       cell_input: %w[A B C],
                                       annotation_input: [
                                         { name: 'species', type: 'group', values: %w[dog cat dog] },
                                         { name: 'disease', type: 'group', values: %w[none none measles] }
                                       ])
    @cluster_group = @study.cluster_groups.first
    DotPlotGene.create(
      study: @study,
      study_file: @expression_file,
      cluster_group: @cluster_group,
      gene_symbol: 'Pten',
      exp_scores: {
        'species--group--study' => { dog: [0.5, 0.666], cat: [0.25, 0.333] },
        'disease--group--study' => { none: [0.125, 0.666], measles: [0.75, 0.333] }
      }
    )
    DotPlotGene.create(
      study: @study,
      study_file: @expression_file,
      cluster_group: @cluster_group,
      gene_symbol: 'Agpat2',
      exp_scores: {
        'species--group--study' => { dog: [4.15, 0.666], cat: [2.25, 0.333] },
        'disease--group--study' => { none: [3.125, 0.666], measles: [1.5, 0.333] }
      }
    )
  end

  test 'should load expression scores by annotation' do
    %w[Pten Agpat2].each do |gene_symbol|
      %w[species disease].each do |annotation_name|
        gene = DotPlotGene.find_by(gene_symbol:, study: @study, cluster_group: @cluster_group)
        assert gene.present?
        assert_equal gene_symbol.downcase, gene.searchable_gene
        metadata = @study.cell_metadata.by_name_and_type(annotation_name, 'group')
        annotation = { name: annotation_name, scope: 'study', values: metadata.values }
        scores = gene.scores_by_annotation(annotation[:name], annotation[:scope], annotation[:values])
        annotation[:values].each_with_index do |value, index|
          identifier = "#{annotation[:name]}--group--study"
          assert_equal scores[index], gene.exp_scores.dig(identifier, value)
        end
        assert_equal [0.0, 0.0],
                     gene.scores_by_annotation(annotation[:name], annotation[:scope], ['nonexistent']).first
      end
    end
  end
end
