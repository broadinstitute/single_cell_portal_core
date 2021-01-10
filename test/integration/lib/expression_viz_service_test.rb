require "test_helper"

class ExpressionVizServiceTest < ActiveSupport::TestCase
  include Minitest::Hooks
  include SelfCleaningSuite
  include TestInstrumentor

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study, name_prefix: 'Basic Viz', test_array: @@studies_to_clean)
    @basic_study_cluster_file = FactoryBot.create(:cluster_file,
                                              name: 'cluster_1.txt', study: @basic_study,
                                              cell_input: {
                                                  x: [1, 4 ,6],
                                                  y: [7, 5, 3],
                                                  z: [2, 8, 9],
                                                  cells: ['A', 'B', 'C']
                                              },
                                              x_axis_label: 'PCA 1',
                                              y_axis_label: 'PCA 2',
                                              z_axis_label: 'PCA 3',
                                              cluster_type: '3d',
                                              annotation_input: [
                                                  {name: 'Category', type: 'group', values: ['bar', 'bar', 'baz']},
                                                  {name: 'Intensity', type: 'numeric', values: [1.1, 2.2, 3.3]}
                                              ])
    @basic_study_exp_file = FactoryBot.create(:study_file,
                                                  name: 'dense.txt',
                                                  file_type: 'Expression Matrix',
                                                  study: @basic_study)

    @study_metadata_file = FactoryBot.create(:metadata_file,
                                             name: 'metadata.txt', study: @basic_study,
                                             cell_input: ['A', 'B', 'C'],
                                             annotation_input: [
                                                 {name: 'species', type: 'group', values: ['dog', 'cat', 'dog']},
                                                 {name: 'disease', type: 'group', values: ['none', 'none', 'measles']}
                                             ])

    @pten_gene = FactoryBot.create(:gene_with_expression,
                                   name: 'PTEN',
                                   study_file: @basic_study_exp_file,
                                   expression_input: [['A', 0],['B', 3],['C', 1.5]])
    @agpat2_gene = FactoryBot.create(:gene_with_expression,
                                     name: 'AGPAT2',
                                     study_file: @basic_study_exp_file,
                                     expression_input: [['A', 0],['B', 0],['C', 8]])
    defaults = {
        cluster: 'cluster_1.txt',
        annotation: 'species--group--study'
    }
    @basic_study.update(default_options: defaults)
  end

  # convenience method to load all gene expression data for a given study like requests to expression_controller
  def load_all_genes(study)
    gene_names = %w(PTEN AGPAT2)
    matrix_ids = study.expression_matrix_files.pluck(:id)
    gene_names.map {|gene| study.genes.by_name_or_id(gene, matrix_ids)}
  end

  test 'can find annotation for cluster' do
    cluster = @basic_study.default_cluster
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster, 'Category', 'group', 'cluster')
    assert_equal 'Category', annotation[:name]
    assert_equal ['bar', 'baz'], annotation[:values]
    metadata = @basic_study.cell_metadata.first
    study_annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster, metadata.name, metadata.annotation_type, 'study')
    assert_equal metadata.name, study_annotation[:name]
    assert_equal metadata.values, study_annotation[:values]
  end

  test 'should parse legacy annotation params' do
    default_annot = @basic_study.default_annotation
    params = {annotation: default_annot}
    annot_keys = [:name, :type, :scope]
    expected_annotation = Hash[annot_keys.zip(default_annot.split('--'))]
    loaded_annotation = ExpressionVizService.parse_annotation_legacy_params(@basic_study, params)
    assert_equal expected_annotation, loaded_annotation
  end

  test 'should get global gene search render data' do
    cluster = @basic_study.default_cluster
    default_annot = @basic_study.default_annotation
    annot_name, annot_type, annot_scope = default_annot.split('--')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster, annot_name, annot_type, annot_scope)
    gene = @basic_study.genes.by_name_or_id('PTEN', @basic_study.expression_matrix_files.pluck(:id))
    rendered_data = ExpressionVizService.get_global_expression_render_data(
      study: @basic_study,
      subsample: nil,
      genes: [gene],
      cluster: cluster,
      selected_annotation: annotation,
      boxpoints: 'All',
      current_user: @user
    )
    expected_values = %w(dog cat)
    assert_equal expected_values, rendered_data[:values].keys
    expected_annotations = %w(Category disease Intensity species).sort
    loaded_annotations = rendered_data[:annotation_list][:annotations].map{|a| a[:name]}.sort
    assert_equal expected_annotations, loaded_annotations
    assert_equal cluster.name, rendered_data[:rendered_cluster]
    assert_equal default_annot, rendered_data[:rendered_annotation]
    # expression scores for 'dog'
    expected_expression = [0, 1.5]
    expected_cells = %w(A C)
    assert_equal expected_expression, rendered_data[:values].dig('dog', :y)
    assert_equal expected_cells, rendered_data[:values].dig('dog', :cells)
  end

  test 'should load ideogram outputs' do
    # we need a non-detached study, so create one
    study = FactoryBot.create(:study, name: "Ideogram Study #{SecureRandom.uuid}", test_array: @@studies_to_clean)

    cluster_file = FactoryBot.create(:cluster_file,
                                     name: 'cluster_1.txt', study: study,
                                     cell_input: {
                                         x: [1, 4 ,6],
                                         y: [7, 5, 3],
                                         cells: ['A', 'B', 'C']
                                     },
                                     x_axis_label: 'PCA 1',
                                     y_axis_label: 'PCA 2',
                                     cluster_type: '3d',
                                     annotation_input: [
                                         {name: 'Category', type: 'group', values: ['bar', 'bar', 'baz']}
                                     ])
    study.update(default_options: {cluster: cluster_file.name, annotation: 'Category--group--cluster'})
    cluster = study.default_cluster
    annotation = study.default_annotation
    filename = 'ideogram_annotations.json'
    ideogram_file = FactoryBot.create(:ideogram_output,
                                      study: study,
                                      name: filename,
                                      cluster: cluster,
                                      annotation: annotation)

    ideogram_output = ExpressionVizService.get_infercnv_ideogram_files(study)
    assert_equal 1, ideogram_output.size
    ideogram_opts = ideogram_output[ideogram_file.id.to_s]
    assert_equal ideogram_opts[:cluster], cluster.name
    assert_equal annotation, ideogram_opts[:annotation]
  end

  test 'should load expression axis label' do
    assert_equal 'Expression', ExpressionVizService.load_expression_axis_title(@basic_study)
    label = 'log(TPM)'
    @basic_study.default_options = @basic_study.default_options.merge({expression_label: label})
    assert_equal label, ExpressionVizService.load_expression_axis_title(@basic_study)
  end

  test 'should initialize visualization object from annotation' do
    cluster = @basic_study.default_cluster
    default_annot = @basic_study.default_annotation
    annot_name, annot_type, annot_scope = default_annot.split('--')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster, annot_name, annot_type, annot_scope)
    plotly_struct = ExpressionVizService.initialize_plotly_objects_by_annotation(annotation)
    annotation[:values].each do |value|
      trace = plotly_struct[value]
      assert trace.present?, "Did not find #{name} in #{plotly_struct.keys}"
      assert_equal value, trace[:name]
    end
  end

  # test group-based violin plot data
  test 'should load violin plot data' do
    gene = @basic_study.genes.by_name_or_id('PTEN', @basic_study.expression_matrix_files.pluck(:id))
    cluster = @basic_study.default_cluster
    default_annot = @basic_study.default_annotation
    annot_name, annot_type, annot_scope = default_annot.split('--')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster, annot_name, annot_type, annot_scope)
    violin_data = ExpressionVizService.load_expression_boxplot_data_array_scores(@basic_study, gene, cluster, annotation)
    # cells A & C belong to 'dog', and cell B belongs to 'cat' from default metadata annotation
    expected_output = {
        dog: {y: [0.0, 1.5], cells: %w(A C), annotations: [], name: 'dog'},
        cat: {y: [3.0], cells: %w(B), annotations: [], name: 'cat'}
    }
    assert_equal expected_output.with_indifferent_access, violin_data.with_indifferent_access
  end

  # test numeric annotation-based 2d scatter plots, showing expression vs. numeric annotation values
  test 'should load 2d annotation expression scatter' do
    gene = @basic_study.genes.by_name_or_id('PTEN', @basic_study.expression_matrix_files.pluck(:id))
    cluster = @basic_study.default_cluster
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster, 'Intensity', 'numeric', 'cluster')
    scatter_data = ExpressionVizService.load_annotation_based_data_array_scatter(@basic_study, gene, cluster, annotation,
                                                                                 nil, @basic_study.default_expression_label)
    expected_x_data = [1.1, 2.2, 3.3]
    expected_exp_data = [0.0, 3.0, 1.5]
    expected_cells = %w(A B C)
    assert_equal expected_x_data, scatter_data[:all][:x]
    assert_equal expected_exp_data, scatter_data[:all][:y]
    assert_equal expected_cells, scatter_data[:all][:cells]
  end

  # test normal scatter plot with expression values overlaid, instead of annotations
  test 'should load expression based scatter plot' do
    gene = @basic_study.genes.by_name_or_id('PTEN', @basic_study.expression_matrix_files.pluck(:id))
    cluster = @basic_study.default_cluster
    default_annot = @basic_study.default_annotation
    annot_name, annot_type, annot_scope = default_annot.split('--')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster, annot_name, annot_type, annot_scope)
    expression_scatter = ExpressionVizService.load_expression_data_array_points(@basic_study, gene, cluster, annotation,
                                                                                nil, @basic_study.default_expression_label,
                                                                                'Blues')
    expected_x_data = cluster.concatenate_data_arrays('x', 'coordinates')
    expected_y_data = cluster.concatenate_data_arrays('y', 'coordinates')
    expected_z_data = cluster.concatenate_data_arrays('z', 'coordinates')
    expected_exp_data = [0.0, 3.0, 1.5]
    assert_equal expected_x_data, expression_scatter[:all][:x]
    assert_equal expected_y_data, expression_scatter[:all][:y]
    assert_equal expected_z_data, expression_scatter[:all][:z]
    assert_equal expected_exp_data, expression_scatter[:all][:marker][:color]
    assert_equal @basic_study.default_expression_label, expression_scatter[:all][:marker][:colorbar][:title]
    assert_equal 'Blues', expression_scatter[:all][:marker][:colorscale]
  end

  test 'should load gene set violin plots' do
    genes = load_all_genes(@basic_study)
    cluster = @basic_study.default_cluster
    default_annot = @basic_study.default_annotation
    annot_name, annot_type, annot_scope = default_annot.split('--')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster, annot_name, annot_type, annot_scope)
    gene_set_violin = ExpressionVizService.load_gene_set_expression_boxplot_scores(@basic_study, genes, cluster, annotation,
                                                                                   'mean')
    # cells A & C belong to 'dog', and cell B belongs to 'cat' from default metadata annotation
    # expression values for A: [0,0].mean (0), B: [1.5,8].mean (4.75), C: [0,3].mean (1.5)
    expected_set_expression = {
        dog: {y: [0.0, 4.75], cells: %w(A C), annotations:[], name: 'dog'},
        cat: {y: [1.5], cells: %w(B), annotations:[], name: 'cat'}
    }
    assert_equal expected_set_expression.with_indifferent_access, gene_set_violin.with_indifferent_access
  end

  # test numeric annotation-based 2d scatter plots, showing expression vs. numeric annotation values for multiple genes
  test 'should load gene set 2d annotation expression scatter' do
    genes = load_all_genes(@basic_study)
    cluster = @basic_study.default_cluster
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster, 'Intensity', 'numeric', 'cluster')
    gene_set_annot_scatter = ExpressionVizService.load_gene_set_annotation_based_scatter(
        @basic_study, genes, cluster, annotation, 'mean', nil, @basic_study.default_expression_label
    )

    # mean of values for scores across both genes for each cell
    # A: [0, 0].mean (0), B: [0, 3].mean (1.5), C: [1,8].mean (4.75)
    expected_exp_data = [0.0, 1.5, 4.75]
    expected_x_data = [1.1, 2.2, 3.3]
    expected_cells = %w(A B C)
    assert_equal expected_x_data, gene_set_annot_scatter[:all][:x]
    assert_equal expected_exp_data, gene_set_annot_scatter[:all][:y]
    assert_equal expected_cells, gene_set_annot_scatter[:all][:cells]
  end

  # test normal scatter plot with gene set expression values overlaid (collapsed by metric), instead of annotations
  test 'should load gene set expression based scatter plot' do
    genes = load_all_genes(@basic_study)
    cluster = @basic_study.default_cluster
    default_annot = @basic_study.default_annotation
    annot_name, annot_type, annot_scope = default_annot.split('--')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster, annot_name, annot_type, annot_scope)
    gene_set_exp_statter = ExpressionVizService.load_gene_set_expression_data_arrays(
        @basic_study, genes, cluster, annotation, 'mean', nil,
        @basic_study.default_expression_label, 'Blues'
    )

    # mean of values for scores across both genes for each cell
    # A: [0, 0].mean (0), B: [0, 3].mean (1.5), C: [1,8].mean (4.75)
    expected_exp_data = [0.0, 1.5, 4.75]
    expected_x_data = cluster.concatenate_data_arrays('x', 'coordinates')
    expected_y_data = cluster.concatenate_data_arrays('y', 'coordinates')
    expected_z_data = cluster.concatenate_data_arrays('z', 'coordinates')
    assert_equal expected_x_data, gene_set_exp_statter[:all][:x]
    assert_equal expected_y_data, gene_set_exp_statter[:all][:y]
    assert_equal expected_z_data, gene_set_exp_statter[:all][:z]
    assert_equal expected_exp_data, gene_set_exp_statter[:all][:marker][:color]
    assert_equal @basic_study.default_expression_label, gene_set_exp_statter[:all][:marker][:colorbar][:title]
    assert_equal 'Blues', gene_set_exp_statter[:all][:marker][:colorscale]
  end

  test 'should collapse by mean/median for gene expression values' do
    genes = load_all_genes(@basic_study)
    # since there are only 2 expression values in each set, mean === median
    cells = %w(A B C)
    means_medians = [0.0, 1.5, 4.75]
    expected_outputs = Hash[cells.zip(means_medians)]
    cells.each do |cell|
      calculated_mean = ExpressionVizService.calculate_mean(genes, cell)
      calculated_median = ExpressionVizService.calculate_median(genes, cell)
      expected_value = expected_outputs[cell]
      assert_equal expected_value, calculated_mean, "Mean calculation incorrect; #{expected_value} != #{calculated_mean}"
      assert_equal expected_value, calculated_median, "Median calculation incorrect; #{expected_value} != #{calculated_median}"
    end
  end
end
