require "test_helper"

class SearchFacetTest < ActiveSupport::TestCase

  def setup
    @search_facet = SearchFacet.first

    # filter_results to return from mock call to BigQuery
    @filter_results = [
        {id: 'NCBITaxon_9606', name: 'Homo sapiens'},
        {id: 'NCBITaxon_10090', name: 'Mus musculus'}
    ]
  end

  # should return expected filters list
  # mocks call to BigQuery to avoid unnecessary overhead
  test 'should update filters list' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # mock call to BQ, until a better library can be found
    mock = Minitest::Mock.new
    mock.expect :query, @filter_results, [String]

    SearchFacet.stub :big_query_dataset, mock do
      filters = @search_facet.get_unique_filter_values
      mock.verify
      assert_equal @filter_results, filters
    end

    puts "#{File.basename(__FILE__)}: #{self.method_name} complete!"
  end

  # should return facet configuration object with name of facet for UI and filter options of id/name
  test 'should return facet config' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    config = @search_facet.facet_config
    assert_equal @search_facet.name, config[:name]
    assert_equal @search_facet.identifier, config[:id]
    assert_equal @search_facet.ontology_urls, config[:links]
    assert_equal @search_facet.filters, config[:filters]

    puts "#{File.basename(__FILE__)}: #{self.method_name} complete!"
  end

  # should generate correct kind of query for DISTINCT filters based on array/non-array columns
  test 'should generate correct distinct queries' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    non_array_query = @search_facet.generate_non_array_query
    non_array_match = /DISTINCT #{@search_facet.big_query_id_column}/
    assert_match non_array_match, non_array_query, "Non-array query did not contain correct DISTINCT clause: #{non_array_query}"
    array_facet = SearchFacet.new(
        name: 'Disease',
        identifier: 'disease',
        is_ontology_based: true,
        is_array_based: true,
        filters: [],
        ontology_urls: [
            {name: 'Monarch Disease Ontology', url: 'https://www.ebi.ac.uk/ols/ontologies/mondo'},
            {name: 'Phenotype And Trait Ontology', url: 'https://www.ebi.ac.uk/ols/ontologies/pato'}
        ],
        big_query_id_column: 'disease',
        big_query_name_column: 'disease__ontology_label',
        convention_name: 'alexandria_convention',
        convention_version: '1.1.3'
    )
    column = array_facet.big_query_id_column
    identifier = 'id'
    array_query = array_facet.generate_array_query(column, identifier)
    array_match = /SELECT DISTINCT #{identifier}.*UNNEST\(#{column}\)/
    assert_match array_match, array_query, "Array query did not correctly name identifier or unnest column: #{array_query}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} complete!"
  end

  # should validate search facet correctly, especially links to external ontologies
  test 'should validate search_facet including ontology urls' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    assert @search_facet.valid?, "Testing search facet did not validate: #{@search_facet.errors.full_messages}"
    invalid_facet = SearchFacet.new
    assert_not invalid_facet.valid?, 'Did not correctly find validation errors on empty facet'
    expected_error_count = 6
    invalid_facet_error_count = invalid_facet.errors.size
    assert_equal expected_error_count, invalid_facet_error_count,
           "Did not find correct number of errors; expected #{expected_error_count} but found #{invalid_facet_error_count}"
    @search_facet.ontology_urls = []
    assert_not @search_facet.valid?, 'Did not correctly find validation errors on invalid facet'
    assert_equal @search_facet.errors.to_hash[:ontology_urls].first,
                 'cannot be empty if SearchFacet is ontology-based'
    @search_facet.ontology_urls = [{name: 'My Ontology', url: 'not a url'}]
    assert_not @search_facet.valid?, 'Did not correctly find validation errors on invalid facet'
    assert_equal @search_facet.errors.to_hash[:ontology_urls].first,
                 'contains an invalid URL: not a url'

    puts "#{File.basename(__FILE__)}: #{self.method_name} complete!"
  end
end
