FactoryBot.define do
  # create a cell_metadatum with data arrays based on a passed in annotation_input object
  factory :cell_metadatum do
    study { study_file.study }

    transient do
      # cell_input is an array of all cell names
      # e.g.  ['cellA', 'cellB', 'cellC']
      cell_input { [] }
      # annotation_input is an array of annotation values
      # e.g.  ['foo', 'foo', 'bar']
      annotation_input { {} }
    end
    values {
      annotation_input[:values].uniq
    }
    name { annotation_input[:name] }
    annotation_type { annotation_input[:type] }
    is_differential_expression_enabled { false }

    after(:create) do |metadata, evaluator|
      FactoryBot.create(:data_array,
                        array_type: 'annotations',
                        name: metadata[:name],
                        array_index: 0,
                        values: evaluator.annotation_input[:values],
                        study_file: evaluator.study_file,
                        cell_metadatum: metadata)
    end
  end
end
