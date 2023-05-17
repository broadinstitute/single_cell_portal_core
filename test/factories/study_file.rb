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
        evaluator.expression_input.each do |gene, expression|
          FactoryBot.create(:gene_with_expression,
                            expression_input: expression,
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
      end
      after(:create) do |file, evaluator|
        file.build_ann_data_file_info
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
        evaluator.coordinate_input.each do |entry|
          entry.each do |cluster_name, axes|
            file.ann_data_file_info.has_clusters = true
            axes_and_cells = axes.merge(cells: evaluator.cell_input)
            FactoryBot.create(:cluster_group_with_cells,
                              name: cluster_name,
                              cell_input: axes_and_cells,
                              cluster_type: "#{axes.keys.size}d",
                              study_file: file)
          end
        end
        # gotcha to save updates to ann_data_file_info
        file.ann_data_file_info.save
      end
    end
  end
end
