require 'test_helper'

class DifferentialExpressionFileInfoTest < ActiveSupport::TestCase

  before(:all) do
    cells = %w[A B C D E F G]
    coords = [1, 2, 3, 4, 5, 6, 7]
    cell_types = ['B cell', 'T cell', 'B cell', 'T cell', 'T cell', 'B cell', 'B cell']
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study, name_prefix: 'DE Test', user: @user, test_array: @@studies_to_clean)
    FactoryBot.create(:metadata_file, name: 'metadata.txt', study: @study, cell_input: cells, annotation_input: [
      { name: 'cell_type__ontology_label', type: 'group', values: cell_types },
    ])
    FactoryBot.create(:cluster_file, name: 'cluster.txt', study: @study, cell_input: { x: coords, y: coords, cells: })
  end

  test 'should validate user-uploaded differential expression file' do
    de_file = FactoryBot.create(:study_file,
                                study: @study,
                                file_type: 'Differential Expression',
                                name: 'de.txt')
    annotation_name = 'cell_type__ontology_label'
    annotation_scope = 'study'
    de_info = de_file.build_differential_expression_file_info(annotation_name:, annotation_scope:)
    cluster = @study.cluster_groups.by_name('cluster.txt')
    de_info.cluster_group = cluster
    de_file.save
    assert de_file.valid?
    assert de_file.differential_expression_file_info.valid?
    metadata = @study.cell_metadata.by_name_and_type(annotation_name, 'group')
    assert_equal metadata.id, de_info.annotation_object.id

    # test annotation validation
    de_info.annotation_name = 'foo'
    assert_not de_info.valid?
    de_info.annotation_name = annotation_name
    assert de_info.valid?
    de_info.annotation_scope = 'user'
    assert_not de_info.valid?
  end
end
