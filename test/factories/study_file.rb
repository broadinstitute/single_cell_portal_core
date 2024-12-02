# factory for study_file test objects.
FactoryBot.define do
  factory :study_file do
    upload_file_name { name }
    factory :metadata_file do
      file_type { 'Metadata' }
      parse_status { 'parsed' }
      transient do
        # cell_input is an array of all cell names
        # e.g.  ['cellA', 'cellB', 'cellC']
        cell_input { [] }
        # annotation_input is an array of objects specifying name, type, and values for annotations
        # values should be an array in the same length and order as the 'cells' array above
        # e.g. [{ name: 'category', type: 'group', values: ['foo', 'foo', 'bar'] }]
        annotation_input { [] }
      end
      after(:create) do |file, evaluator|
        evaluator.annotation_input.each do |annotation|
          FactoryBot.create(:cell_metadatum,
                            annotation_input: annotation,
                            study_file: file)

        end
        if !evaluator.cell_input.empty?
          FactoryBot.create(:data_array,
                            array_type: 'cells',
                            name: 'All Cells',
                            array_index: 0,
                            values: evaluator.cell_input,
                            study_file: file)
        end
        file.study.create_all_cluster_cell_indices!
      end
    end
    factory :cluster_file do
      # Rough performance timing in local (non-dockerized) development suggests that crating a user
      # using this factory to create a sample cluster file with cells and annotations takes ~1.5 seconds
      # a cluster file without cells and annotations takes ~0.5secods
      file_type { 'Cluster' }
      parse_status { 'parsed' }
      is_spatial { false }
      transient do
        # cell_input is a hash of three (or 4) arrays: cells, x and y and z
        # {
        #   x: [1, 2, 3],
        #   y: [1, 2, 3],
        #   cells: ['cellA', 'cellB', 'cellC']
        # }
        cell_input {
          {}
        }
        cluster_type { cell_input.dig(:z).present? ? '3d' : '2d' }
        # annotation_input is an array of objects specifying name, type, and values for annotations
        # values should be an array in the same length and order as the 'cells' array above
        # e.g. [{ name: 'category', type: 'group', values: ['foo', 'foo', 'bar'] }]
        annotation_input { [] }
      end
      after(:create) do |file, evaluator|
        FactoryBot.create(:cluster_group_with_cells,
                          annotation_input: evaluator.annotation_input,
                          cell_input: evaluator.cell_input,
                          cluster_type: evaluator.cluster_type,
                          study_file: file)
      end
    end
    factory :expression_file do
      file_type { 'Expression Matrix' }
      parse_status { 'parsed' }
      transient do
        # expression_input is a hash of gene names to expression values
        # expression values should be an array of arrays, where each sub array is a cellName->value pair
        # e.g.
        # {
        #   farsa: [['cellA', 0.0],['cellB', 1.1], ['cellC', 0.5]],
        #   phex: [['cellA', 0.6],['cellB', 6.1], ['cellC', 4.5]]
        # }
        expression_input { {} }
      end
      after(:create) do |file, evaluator|
        if evaluator.expression_input.any?
          cells = evaluator.expression_input.values.map { |vals| vals.map(&:first) }.flatten.uniq
          FactoryBot.create(:data_array,
                            array_type: 'cells',
                            array_index: 0,
                            name: "#{file.name} Cells",
                            cluster_name: file.name,
                            values: cells,
                            study_file: file
          )
        end
        evaluator.expression_input.each do |gene, expression|
          FactoryBot.create(:gene_with_expression,
                            expression_input: expression,
                            name: gene,
                            study_file: file)
        end
      end
    end
    factory :coordinate_label_file do
      file_type { 'Coordinate Labels' }
      parse_status { 'parsed' }
      transient do
        # label input is used for coordinate-based annotations
        label_input {}
        # cluster is for setting cluster_group_id on data_arrays
        cluster {}
      end
      after(:create) do |file, evaluator|
        evaluator.label_input.each do |axis, values|
          FactoryBot.create(:data_array,
                            array_type: 'labels',
                            array_index: 0,
                            name: axis,
                            cluster_group: evaluator.cluster,
                            values: values,
                            study_file: file
          )
        end
      end
    end
    factory :ideogram_output do
      file_type { 'Analysis Output'}
      transient do
        cluster {}
        annotation {}
      end
      options {
        {
            analysis_name: 'infercnv',
            visualization_name: 'ideogram.js',
            cluster_name: cluster.try(:name),
            annotation_name: annotation
        }
      }
    end
    factory :gene_list do
      file_type { 'Gene List' }
      parse_status { 'parsed' }
      transient do
        list_name {}
        clusters_input {}
        gene_scores_input {}
      end
      after(:create) do |file, evaluator|
        FactoryBot.create(:precomputed_score,
                          name: evaluator.list_name,
                          clusters: evaluator.clusters_input,
                          gene_scores: evaluator.gene_scores_input,
                          study_file: file)
      end
    end
    factory :ann_data_file do
      file_type { 'AnnData' }
      parse_status { 'parsed' }
      transient do
        # cell_input is an array of all cell names
        # e.g.  ['cellA', 'cellB', 'cellC']
        cell_input { [] }
        # coordinate_input is an array of hashes of axes and values where the key is the name of the cluster
        # e.g. [ { tsne: { x: [1,2,3], y: [4,5,6] } }, { umap: ... }]
        # cell names are used from above
        coordinate_input { [] }
        # annotation_input is an array of objects specifying name, type, and values for annotations
        # values should be an array in the same length and order as the 'cells' array above
        # e.g. [{ name: 'category', type: 'group', values: ['foo', 'foo', 'bar'] }]
        annotation_input { [] }
        # expression_input is a hash of gene names to expression values
        # expression values should be an array of arrays, where each sub array is a cellName->value pair
        # e.g.
        # {
        #   farsa: [['cellA', 0.0],['cellB', 1.1], ['cellC', 0.5]],
        #   phex: [['cellA', 0.6],['cellB', 6.1], ['cellC', 4.5]]
        # }
        expression_input { {} }
        has_raw_counts { expression_input.any? && cell_input.any? }
        reference_file { cell_input.empty? && coordinate_input.empty? && annotation_input.empty? && expression_input.empty? }
      end
      after(:create) do |file, evaluator|
        file.build_ann_data_file_info
        file.ann_data_file_info.reference_file = evaluator.reference_file
        evaluator.annotation_input.each do |annotation|
          file.ann_data_file_info.has_metadata = true
          FactoryBot.create(:cell_metadatum,
                            annotation_input: annotation,
                            study_file: file)
        end
        if evaluator.cell_input.any?
          FactoryBot.create(:data_array,
                            array_type: 'cells',
                            name: 'All Cells',
                            array_index: 0,
                            values: evaluator.cell_input,
                            study_file: file)
        end
        if evaluator.expression_input.any?
          file.build_expression_file_info(library_preparation_protocol: "10x 5' v3")
          file.ann_data_file_info.has_expression = true
          if evaluator.has_raw_counts
            file.expression_file_info.is_raw_counts = evaluator.has_raw_counts
            file.expression_file_info.units = 'raw counts'
            file.ann_data_file_info.has_raw_counts = evaluator.has_raw_counts
          end
          file.expression_file_info.save
          matrix_types = %w[processed]
          matrix_types << 'raw' if evaluator.has_raw_counts
          matrix_types.each do |matrix_type|
            FactoryBot.create(:data_array,
                              array_type: 'cells',
                              array_index: 0,
                              name: "h5ad_frag.matrix.#{matrix_type}.mtx.gz Cells",
                              cluster_name: "h5ad_frag.matrix.#{matrix_type}.mtx.gz",
                              values: evaluator.cell_input,
                              study_file: file
            )
          end

          evaluator.expression_input.each do |gene, expression|
            FactoryBot.create(:gene_with_expression,
                              expression_input: expression,
                              name: gene,
                              study_file: file)
          end
        end
        evaluator.coordinate_input.each do |entry|
          entry.each do |name, axes|
            file.ann_data_file_info.has_clusters = true
            axes_and_cells = axes.merge(cells: evaluator.cell_input)
            FactoryBot.create(:cluster_group_with_cells,
                              name:,
                              cell_input: axes_and_cells,
                              cluster_type: "#{axes.keys.size}d",
                              study_file: file)
            file.ann_data_file_info.data_fragments << {
              _id: BSON::ObjectId.new.to_s, data_type: :cluster, obsm_key_name: "X_#{name}", name:
            }.with_indifferent_access
          end
        end
        # gotcha to save updates to ann_data_file_info
        file.ann_data_file_info.save
      end
    end
    factory :differential_expression_file do
      file_type { 'Differential Expression' }
      parse_status { 'parsed' }
      transient do
        cluster_group {}
        annotation_name {}
        annotation_scope {}
        computational_method {}
        gene_header {}
        group_header {}
        comparison_group_header {}
        size_metric {}
        significance_metric {}
      end
      after(:create) do |file, evaluator|
        file.build_differential_expression_file_info
        file.differential_expression_file_info.cluster_group = evaluator.cluster_group
        file.differential_expression_file_info.annotation_name = evaluator.annotation_name
        file.differential_expression_file_info.annotation_scope = evaluator.annotation_scope
        file.differential_expression_file_info.computational_method = evaluator.computational_method
        file.differential_expression_file_info.gene_header = evaluator.gene_header
        file.differential_expression_file_info.group_header = evaluator.group_header
        file.differential_expression_file_info.size_metric = evaluator.size_metric
        file.differential_expression_file_info.comparison_group_header = evaluator.comparison_group_header
        file.differential_expression_file_info.significance_metric = evaluator.significance_metric
        file.save
      end
    end
  end
end
