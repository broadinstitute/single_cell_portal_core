require 'test_helper'

class DotPlotServiceTest < ActiveSupport::TestCase
  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'DotPlotService Test Study',
                               user: @user,
                               test_array: @@studies_to_clean)
    cells = %w[A B C]
    genes = %w[pten agpat2]
    expression_input = genes.index_with(cells.map { |c| [c, rand.floor(3)] })
    @cluster_file = FactoryBot.create(:cluster_file,
                                      name: 'cluster_example.txt',
                                      study: @study,
                                      cell_input: { x: cells, y: cells })
    @expression_file = FactoryBot.create(:expression_file,
                                         name: 'expression_example.txt',
                                         study: @study,
                                         expression_input:)
    @metadata_file = FactoryBot.create(:metadata_file,
                                       name: 'metadata.txt',
                                       study: @study,
                                       cell_input: cells,
                                       annotation_input: [
                                         { name: 'species', type: 'group', values: %w[dog cat dog] },
                                         { name: 'disease', type: 'group', values: %w[none none measles] }
                                       ])
    @cluster_group = @study.cluster_groups.first
  end

  test 'should determine study eligibility for preprocessing' do
    assert DotPlotService.study_eligible?(@study)
    empty_study = FactoryBot.create(:detached_study,
                                    name_prefix: 'Empty DotPlot',
                                    user: @user,
                                    test_array: @@studies_to_clean)
    assert_not DotPlotService.study_eligible?(empty_study)
  end

  test 'should determine if cluster has been processed' do
    assert_not DotPlotService.cluster_processed?(@study, @cluster_group)
    DotPlotGene.create(
      study: @study,
      study_file: @expression_file,
      cluster_group: @cluster_group,
      gene_symbol: 'Pten',
      exp_scores: {}
    )
    assert DotPlotService.cluster_processed?(@study, @cluster_group)
  end

  test 'should get processed matrices for study' do
    assert_includes DotPlotService.study_processed_matrices(@study), @expression_file
    empty_study = FactoryBot.create(:detached_study,
                                    name_prefix: 'Empty DotPlot',
                                    user: @user,
                                    test_array: @@studies_to_clean)
    assert_empty DotPlotService.study_processed_matrices(empty_study)
  end

  test 'should run preprocess expression job' do
    assert DotPlotService.run_preprocess_expression_job(@study, @cluster_group, @metadata_file, @expression_file)
  end
end
