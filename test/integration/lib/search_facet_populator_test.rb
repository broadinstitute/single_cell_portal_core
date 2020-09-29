require "integration_test_helper"

class SearchFacetPopulatorTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test 'populate facets from alexandria convention data' do
    SearchFacet.destroy_all
    SearchFacetPopulator.populate_from_schema
    assert_equal 8, SearchFacet.count

    # spot-check a couple of facets
    disease_facet = SearchFacet.find_by(name: 'disease')
    assert_equal true, disease_facet.is_ontology_based
    assert_equal true, disease_facet.is_array_based
    assert_equal 'https://www.ebi.ac.uk/ols/api/ontologies/mondo', disease_facet.ontology_urls.first['url']
    assert_equal 'https://www.ebi.ac.uk/ols/ontologies/mondo', disease_facet.ontology_urls.first['browser_url']
    assert_equal 'Mondo Disease Ontology', disease_facet.ontology_urls.first['name']

    sex_facet = SearchFacet.find_by(name: 'sex')
    assert_equal false, sex_facet.is_ontology_based
    assert_equal false, sex_facet.is_array_based
    assert_equal [], sex_facet.ontology_urls

  end

  test 'updates existing facets' do
    SearchFacet.destroy_all
    SearchFacet.create!(name: "disease",
                        identifier: "disease",
                        is_ontology_based: true,
                        is_array_based: false,
                        big_query_id_column: 'disease',
                        big_query_name_column: 'disease__ontology_label',
                        convention_name: 'Alexandria Metadata Convention',
                        convention_version: '1.1.3',
                        ontology_urls: [{
                          name: 'MONDO: Monarch Disease Ontology',
                          url: 'https://www.ebi.ac.uk/ols/api/ontologies/mondo',
                          browser_url: nil
                        }])
    SearchFacetPopulator.populate_from_schema
    assert_equal 8, SearchFacet.count

    # spot-check a couple of facets
    disease_facet = SearchFacet.find_by(name: 'disease')
    assert_equal true, disease_facet.is_ontology_based
    assert_equal true, disease_facet.is_array_based
    assert_equal 'https://www.ebi.ac.uk/ols/api/ontologies/mondo', disease_facet.ontology_urls.first['url']
    assert_equal 'Mondo Disease Ontology', disease_facet.ontology_urls.first['name']
    assert_equal 'https://www.ebi.ac.uk/ols/ontologies/mondo', disease_facet.ontology_urls.first['browser_url']
    assert_not_equal disease_facet.convention_version, '1.1.3'
  end
end
