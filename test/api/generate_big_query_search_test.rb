require "test_helper"

# Testing the and/or and filter logic is correctly generated for querying BQ
class GenerateBigQuerySearchTest < ActiveSupport::TestCase
  def setup
    @sample_disease_facet = ::SearchFacet.new(identifier: 'disease',
                                              name: 'disease',
                                              filters: [{id: 'd1', name: 'tuberculosis'}, {id: 'd2', name: 'psoriasis'}],
                                              is_array_based: true,
                                              data_type: 'string',
                                              big_query_id_column: 'disease',
                                              big_query_name_column: 'disease__ontology_label')
    @sample_species_facet = ::SearchFacet.new(identifier: 'species',
                                              name: 'species',
                                              filters: [{id: 's1', name: 'mus musculus'}, {id: 's2', name: 'homo sapiens'}],
                                              is_array_based: false,
                                              data_type: 'string',
                                              big_query_id_column: 'species',
                                              big_query_name_column: 'species__ontology_label')
    @sample_age_facet = ::SearchFacet.new(identifier: 'organism_age',
                                               name: 'age',
                                               filters: [],
                                               is_array_based: false,
                                               data_type: 'number',
                                               min: 1.0,
                                               max: 180.0,
                                               big_query_id_column: 'organism_age',
                                               big_query_name_column: 'organism_age',
                                               big_query_conversion_column: 'organism_age__seconds')
    @sample_celltype_facet = ::SearchFacet.new(identifier: 'cell_type',
                                               name: 'cell type',
                                               filters: [{id: 'c1', name: 'amarcrine'}, {id: 'c2', name: 't cell'}],
                                               is_array_based: false,
                                               data_type: 'string',
                                               big_query_id_column: 'cell_type',
                                               big_query_name_column: 'cell_type__ontology_label')
    @sample_celltype_custom_facet = ::SearchFacet.new(identifier: 'cell_type__custom',
                                                      name: 'cell type custom',
                                                      filters: [{id: 'cc1', name: 'amarcrineSP'}, {id: 'cc2', name: 't cell SP'}],
                                                      is_array_based: false,
                                                      data_type: 'string',
                                                      big_query_id_column: 'cell_type__custom',
                                                      big_query_name_column: 'cell_type__custom')
  end



  test 'should generate correct bigQuery query for a single array-based facet' do
    facets = [{id: 'disease',
               db_facet: @sample_disease_facet,
               filters: [{id: 'd1', name: 'tuberculosis'}]}]
    query_string = Api::V1::SearchController.generate_bq_query_string(facets)
    expected_query = 'WITH disease_filters AS (SELECT["d1"] as disease_value) SELECT DISTINCT study_accession, disease_val '\
                     'FROM alexandria_convention, disease_filters, UNNEST(disease_filters.disease_value) AS disease_val '\
                     'WHERE (disease_val IN UNNEST(disease))'
    assert_equal expected_query, query_string
  end

  test 'should generate correct bigQuery query for a single numeric facet' do
    facets = [{id: 'organism_age',
               db_facet: @sample_age_facet,
               filters: {min: 5, max: 40, unit: 'years'}}]
    query_string = Api::V1::SearchController.generate_bq_query_string(facets)
    expected_query = 'SELECT DISTINCT study_accession, organism_age FROM alexandria_convention WHERE organism_age__seconds BETWEEN 157788000.0 AND 1262304000.0'
    assert_equal expected_query, query_string
  end

  test 'should generate correct bigQuery query for two facets' do
    facets = [{
                id: 'disease',
                db_facet: @sample_disease_facet,
                filters: [{id: 'd1', name: 'tuberculosis'}]
              },{
                id: 'species',
                db_facet: @sample_species_facet,
                filters: [{id: 's1', name: 'human'}, {id: 's2', name: 'mouse'}]
              }]
    query_string = Api::V1::SearchController.generate_bq_query_string(facets)
    expected_query = "WITH disease_filters AS (SELECT[\"d1\"] as disease_value) "\
                     "SELECT DISTINCT study_accession, disease_val, species "\
                     "FROM alexandria_convention, disease_filters, UNNEST(disease_filters.disease_value) AS disease_val "\
                     "WHERE (disease_val IN UNNEST(disease)) AND species IN ('s1','s2')"
    assert_equal expected_query, query_string

    facets = [{
                id: 'sample_celltype_facet',
                db_facet: @sample_celltype_facet,
                filters: [{id: 'c1', name: 'amarcrine'}]
              },{
                id: 'species',
                db_facet: @sample_species_facet,
                filters: [{id: 's2', name: 'mouse'}]
              }]
    query_string = Api::V1::SearchController.generate_bq_query_string(facets)
    expected_query = "SELECT DISTINCT study_accession, cell_type, species "\
                     "FROM alexandria_convention "\
                     "WHERE cell_type IN ('c1') AND species IN ('s2')"
    assert_equal expected_query, query_string
  end



  test 'should generate correct bigQuery query for OR-joined facets' do
    facets = [{
                id: 'disease',
                db_facet: @sample_disease_facet,
                filters: [{id: 'd1', name: 'tuberculosis'}]
              },{
                id: 'cell_type',
                db_facet: @sample_celltype_facet,
                filters: [{id: 'c2', name: 't cell'}]
              },{
                id: 'cell_type__custom',
                db_facet: @sample_celltype_custom_facet,
                filters: [{id: 'cc1', name: 'amarcrineSP'}]
              }]
    query_string = Api::V1::SearchController.generate_bq_query_string(facets)
    expected_query = "WITH disease_filters AS (SELECT[\"d1\"] as disease_value) "\
                     "SELECT DISTINCT study_accession, cell_type, cell_type__custom, disease_val "\
                     "FROM alexandria_convention, disease_filters, UNNEST(disease_filters.disease_value) AS disease_val "\
                     "WHERE (cell_type IN ('c2') OR cell_type__custom IN ('cc1')) AND (disease_val IN UNNEST(disease))"
    assert_equal expected_query, query_string
  end
end
