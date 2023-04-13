FactoryBot.define do
  factory :differential_expression_result do
    one_vs_rest_comparisons { [] }
    cluster_name { cluster.name }
    annotation_name { }
    annotation_scope { }
  end
end
