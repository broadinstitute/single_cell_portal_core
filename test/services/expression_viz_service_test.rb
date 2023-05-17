require "test_helper"

class ExpressionVizServiceTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'Basic Viz',
                                     user: @user,
                                     test_array: @@studies_to_clean)
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

    @study_cluster_file_2 = FactoryBot.create(:cluster_file,
                                              name: 'cluster_2.txt', study: @basic_study,
                                              cell_input: {
                                                x: [1, 2, 3],
                                                y: [4, 5, 6],
                                                cells: ['A', 'B', 'C']
                                              },
                                              annotation_input: [
                                                {name: 'Blanks', type: 'group', values: ['bar', 'bar', '']}
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
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: 'Category', annot_type: 'group', annot_scope: 'cluster')
    assert_equal 'Category', annotation[:name]
    assert_equal ['bar', 'baz'], annotation[:values]
    metadata = @basic_study.cell_metadata.first
    study_annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: metadata.name, annot_type: metadata.annotation_type, annot_scope: 'study')
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
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: annot_name, annot_type: annot_type, annot_scope: annot_scope)
    gene = @basic_study.genes.by_name_or_id('PTEN', @basic_study.expression_matrix_files.pluck(:id))
    rendered_data = ExpressionVizService.get_global_expression_render_data(
      study: @basic_study,
      subsample: nil,
      genes: [gene],
      cluster: cluster,
      selected_annotation: annotation,
      boxpoints: 'All',
      consensus: 'nil',
      current_user: @user
    )
    expected_values = %w(dog cat)
    assert_equal expected_values, rendered_data[:values].keys
    expected_annotations = %w(Category disease Intensity species Blanks).sort
    loaded_annotations = rendered_data[:annotation_list][:annotations].map{|a| a[:name]}.sort
    assert_equal expected_annotations, loaded_annotations
    assert_equal cluster.name, rendered_data[:rendered_cluster]
    assert_equal default_annot, rendered_data[:rendered_annotation]
    # expression scores for 'dog'
    expected_expression = [0, 1.5]
    expected_cells = %w(A C)
    assert_equal expected_expression, rendered_data[:values].dig('dog', :y)
    assert_equal expected_cells, rendered_data[:values].dig('dog', :cells)

    # confirm it works for consensus params
    gene2 = @basic_study.genes.by_name_or_id('AGPAT2', @basic_study.expression_matrix_files.pluck(:id))
    rendered_data = ExpressionVizService.get_global_expression_render_data(
      study: @basic_study,
      subsample: nil,
      genes: [gene, gene2],
      cluster: cluster,
      selected_annotation: annotation,
      boxpoints: 'All',
      consensus: 'mean',
      current_user: @user
    )
    assert_equal [0.0, 4.75], rendered_data[:values]['dog'][:y]

    # confirm it works for numeric annotations
    annot_name, annot_type, annot_scope = ['Intensity', 'numeric', 'cluster']
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: annot_name, annot_type: annot_type, annot_scope: annot_scope)
    rendered_data = ExpressionVizService.get_global_expression_render_data(
      study: @basic_study,
      subsample: nil,
      genes: [gene],
      cluster: cluster,
      selected_annotation: annotation,
      boxpoints: 'All',
      consensus: 'nil',
      current_user: @user
    )
    assert_equal [1.1, 2.2, 3.3], rendered_data[:values][:x]
  end


  test 'should load ideogram outputs' do
    # we need a non-detached study, so create one
    study = FactoryBot.create(:detached_study,
                              name: "Ideogram Study #{SecureRandom.uuid}",
                              user: @user,
                              test_array: @@studies_to_clean)

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
    study.update(default_options: {cluster: cluster_file.name, annotation: 'Category--group--cluster'}, detached: false)
    cluster = study.default_cluster
    annotation = study.default_annotation
    filename = 'ideogram_annotations.json'
    ideogram_file = FactoryBot.create(:ideogram_output,
                                      study: study,
                                      name: filename,
                                      cluster: cluster,
                                      annotation: annotation)
    mock = Minitest::Mock.new
    api_url = "https://www.googleapis.com/storage/v1/b/#{study.bucket_id}/o/#{filename}"
    mock.expect :execute_gcloud_method, api_url, [:generate_api_url, Integer, study.bucket_id, filename]
    ApplicationController.stub :firecloud_client, mock do
      ideogram_output = ExpressionVizService.get_infercnv_ideogram_files(study)
      mock.verify
      assert_equal 1, ideogram_output.size
      ideogram_opts = ideogram_output[ideogram_file.id.to_s]
      assert_equal ideogram_opts[:cluster], cluster.name
      assert_equal annotation, ideogram_opts[:annotation]
      assert_equal api_url + '?alt=media', ideogram_opts.dig(:ideogram_settings, :annotationsPath)
    end
    # unset detached to avoid cleanup errors
    study.update(detached: true)
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
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: annot_name, annot_type: annot_type, annot_scope: annot_scope)
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
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: annot_name, annot_type: annot_type, annot_scope: annot_scope)
    violin_data = ExpressionVizService.load_expression_boxplot_data_array_scores(@basic_study, gene, cluster, annotation)
    # cells A & C belong to 'dog', and cell B belongs to 'cat' from default metadata annotation
    expected_output = {
        dog: {y: [0.0, 1.5], cells: %w(A C), annotations: [], name: 'dog'},
        cat: {y: [3.0], cells: %w(B), annotations: [], name: 'cat'}
    }
    assert_equal expected_output.with_indifferent_access, violin_data.with_indifferent_access
  end

  test 'should load violin plot data with blank annotations' do
    gene = @basic_study.genes.by_name_or_id('PTEN', @basic_study.expression_matrix_files.pluck(:id))
    cluster = @basic_study.cluster_groups.by_name('cluster_2.txt')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: 'Blanks', annot_type: 'group', annot_scope: 'cluster')
    violin_data = ExpressionVizService.load_expression_boxplot_data_array_scores(@basic_study, gene, cluster, annotation)
    # cells A & B belong to 'bar', and cell C belongs to the blank label
    expected_output = {
      bar: {y: [0.0, 3.0], cells: %w(A B), annotations: [], name: 'bar'},
      "#{AnnotationVizService::MISSING_VALUE_LABEL}": {y: [1.5], cells: %w(C), annotations: [], name: AnnotationVizService::MISSING_VALUE_LABEL}
    }
    assert_equal expected_output.with_indifferent_access, violin_data.with_indifferent_access
  end

  # test numeric annotation-based 2d scatter plots, showing expression vs. numeric annotation values
  test 'should load 2d annotation expression scatter' do
    gene = @basic_study.genes.by_name_or_id('PTEN', @basic_study.expression_matrix_files.pluck(:id))
    cluster = @basic_study.default_cluster
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: 'Intensity', annot_type: 'numeric', annot_scope: 'cluster')
    scatter_data = ExpressionVizService.load_annotation_based_data_array_scatter(@basic_study, gene, cluster, annotation,
                                                                                 nil)
    assert_equal([1.1, 2.2, 3.3], scatter_data[:x])
    assert_equal([0.0, 3.0, 1.5], scatter_data[:y])
    assert_equal(%w(A B C), scatter_data[:cells])
  end

  # test normal scatter plot with expression values overlaid, instead of annotations
  test 'should load expression based scatter plot' do
    gene = @basic_study.genes.by_name_or_id('PTEN', @basic_study.expression_matrix_files.pluck(:id))
    cluster = @basic_study.default_cluster
    default_annot = @basic_study.default_annotation
    annot_name, annot_type, annot_scope = default_annot.split('--')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: annot_name, annot_type: annot_type, annot_scope: annot_scope)
    expression_scatter = ExpressionVizService.load_expression_data_array_points(@basic_study, [gene], cluster, annotation,
                                                                                nil)
    assert_equal(cluster.concatenate_data_arrays('x', 'coordinates'), expression_scatter[:x])
    assert_equal(cluster.concatenate_data_arrays('y', 'coordinates'), expression_scatter[:y])
    assert_equal(cluster.concatenate_data_arrays('z', 'coordinates'), expression_scatter[:z])
    assert_equal([0.0, 3.0, 1.5], expression_scatter[:expression])
  end

  test 'should load gene set violin plots' do
    genes = load_all_genes(@basic_study)
    cluster = @basic_study.default_cluster
    default_annot = @basic_study.default_annotation
    annot_name, annot_type, annot_scope = default_annot.split('--')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: annot_name, annot_type: annot_type, annot_scope: annot_scope)
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
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: 'Intensity', annot_type: 'numeric', annot_scope: 'cluster')
    gene_set_annot_scatter = ExpressionVizService.load_gene_set_annotation_based_scatter(
        @basic_study, genes, cluster, annotation, 'mean'
    )

    # mean of values for scores across both genes for each cell
    # A: [0, 0].mean (0), B: [0, 3].mean (1.5), C: [1,8].mean (4.75)
    assert_equal([1.1, 2.2, 3.3], gene_set_annot_scatter[:x])
    assert_equal([0.0, 1.5, 4.75], gene_set_annot_scatter[:y])
    assert_equal(%w(A B C), gene_set_annot_scatter[:cells])
  end

  # test normal scatter plot with gene set expression values overlaid (collapsed by metric), instead of annotations
  test 'should load gene set expression based scatter plot' do
    genes = load_all_genes(@basic_study)
    cluster = @basic_study.default_cluster
    default_annot = @basic_study.default_annotation
    annot_name, annot_type, annot_scope = default_annot.split('--')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: annot_name, annot_type: annot_type, annot_scope: annot_scope)
    gene_set_exp_scatter = ExpressionVizService.load_expression_data_array_points(
        @basic_study, genes, cluster, annotation, consensus: 'mean'
    )

    # mean of values for scores across both genes for each cell
    # A: [0, 0].mean (0), B: [0, 3].mean (1.5), C: [1,8].mean (4.75)
    assert_equal(cluster.concatenate_data_arrays('x', 'coordinates'), gene_set_exp_scatter[:x])
    assert_equal(cluster.concatenate_data_arrays('y', 'coordinates'), gene_set_exp_scatter[:y])
    assert_equal(cluster.concatenate_data_arrays('z', 'coordinates'), gene_set_exp_scatter[:z])
    assert_equal([0.0, 1.5, 4.75], gene_set_exp_scatter[:expression])
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

  test 'should load gene correlation visualization' do
    genes = ['PTEN', 'AGPAT2'].map do |gene_name|
      @basic_study.genes.by_name_or_id(gene_name, @basic_study.expression_matrix_files.pluck(:id))
    end
    cluster = @basic_study.default_cluster
    default_annot = @basic_study.default_annotation
    annot_name, annot_type, annot_scope = default_annot.split('--')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: annot_name, annot_type: annot_type, annot_scope: annot_scope)

    viz_data = ExpressionVizService.load_correlated_data_array_scatter(@basic_study, genes, cluster, annotation)
    expected = {:annotations=>["dog", "cat", "dog"], :cells=>["A", "B", "C"], :x=>[0.0, 3.0, 1.5], :y=>[0.0, 0.0, 8.0]}
    assert_equal expected, viz_data
  end
end
