require "test_helper"

class SearchFacetTest < ActiveSupport::TestCase

  def setup
    @search_facet = SearchFacet.find_by(identifier: 'species')

    # filter_results to return from mock call to BigQuery
    @filter_results = [
        {id: 'NCBITaxon_9606', name: 'Homo sapiens'},
        {id: 'NCBITaxon_10090', name: 'Mus musculus'}
    ]

    # mock schema for number_of_reads column in BigQuery
    @column_schema = [{column_name: 'number_of_reads', data_type: 'FLOAT64', is_nullable: 'YES'}]
    # mock minmax query for organism_age query
    @minmax_results = [{MIN: rand(10) + 1, MAX: rand(100) + 10}]
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

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # should generate correct kind of query for DISTINCT filters based on array/non-array columns
  # generate_query_string_by_type should return the correct query string in each case, based on facet type
  test 'should generate correct distinct queries' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    non_array_query = @search_facet.generate_bq_query_string
    non_array_match = /DISTINCT #{@search_facet.big_query_id_column}/
    assert_match non_array_match, non_array_query, "Non-array query did not contain correct DISTINCT clause: #{non_array_query}"
    array_facet = SearchFacet.find_by(identifier: 'disease')
    array_query = array_facet.generate_bq_query_string
    array_match = /SELECT DISTINCT id.*UNNEST\(#{array_facet.big_query_id_column}\) AS id_col WITH OFFSET id_pos.*WHERE id_pos = name_pos/
    assert_match array_match, array_query, "Array query did not correctly unnest column or match offset positions: #{array_query}"
    numeric_facet = SearchFacet.find_by(identifier: 'organism_age')
    numeric_query = numeric_facet.generate_bq_query_string
    numeric_match = /MIN\(#{numeric_facet.big_query_id_column}\).*MAX\(#{numeric_facet.big_query_id_column}\)/
    assert_match numeric_match, numeric_query, "MinMax query did not contain MIN or MAX calls for correct columns: #{numeric_query}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # should validate search facet correctly, especially links to external ontologies
  test 'should validate search_facet including ontology urls' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    assert @search_facet.valid?, "Testing search facet did not validate: #{@search_facet.errors.full_messages}"
    invalid_facet = SearchFacet.new
    assert_not invalid_facet.valid?, 'Did not correctly find validation errors on empty facet'
    expected_error_count = 7
    invalid_facet_error_count = invalid_facet.errors.size
    assert_equal expected_error_count, invalid_facet_error_count,
           "Did not find correct number of errors; expected #{expected_error_count} but found #{invalid_facet_error_count}"
    @search_facet.ontology_urls = []
    assert_not @search_facet.valid?, 'Did not correctly find validation errors on invalid facet'
    assert_equal @search_facet.errors.to_hash[:ontology_urls].first,
                 'cannot be empty if SearchFacet is ontology-based'
    @search_facet.ontology_urls = [{name: 'My Ontology', url: 'not a url', browser_url: nil}]
    assert_not @search_facet.valid?, 'Did not correctly find validation errors on invalid facet'
    assert_equal @search_facet.errors.to_hash[:ontology_urls].first,
                 'contains an invalid URL: not a url'

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should set data_type and is_array_based on create' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    mock = Minitest::Mock.new
    mock.expect :query, @column_schema, [String]

    SearchFacet.stub :big_query_dataset, mock do
      reads_facet = SearchFacet.create(
          name: 'Number of Reads',
          identifier: 'number_of_reads',
          big_query_id_column: 'number_of_reads',
          big_query_name_column: 'number_of_reads',
          is_ontology_based: false,
          convention_name: 'Alexandria Metadata Convention',
          convention_version: '1.1.3'
      )
      mock.verify
      assert_equal 'number', reads_facet.data_type,
                   "Did not correctly set facet data_type, expected 'number' but found '#{reads_facet.data_type}'"
      assert_not reads_facet.is_array_based?,
                   "Did not correctly set is_array_based, expected false but found #{reads_facet.is_array_based?}"
      assert reads_facet.is_numeric?, "Did not correctly return true for is_numeric? with data_type: #{reads_facet.data_type}"

    end

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should set minmax values for numeric facets' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    mock = Minitest::Mock.new
    mock.expect :query, @minmax_results, [String]

    SearchFacet.stub :big_query_dataset, mock do
      age_facet = SearchFacet.find_by(identifier: 'organism_age')
      age_facet.update_filter_values!
      mock.verify
      assert age_facet.must_convert?,
             "Did not correctly return true for must_convert? with conversion column: #{age_facet.big_query_conversion_column}"
      minmax_query = age_facet.generate_minmax_query
      minmax_match = /SELECT MIN\(#{age_facet.big_query_id_column}\).*MAX\(#{age_facet.big_query_id_column}\)/
      assert_match minmax_match, minmax_query, "Minmax query improperly formed: #{minmax_query}"
      assert_equal @minmax_results.first[:MIN], age_facet.min,
                   "Did not set minimum value; expected #{@minmax_results.first[:MIN]} but found #{age_facet.min}"
      assert_equal @minmax_results.first[:MAX], age_facet.max,
                   "Did not set minimum value; expected #{@minmax_results.first[:MAX]} but found #{age_facet.max}"
    end

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should convert time values between units' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    age_facet = SearchFacet.find_by(identifier: 'organism_age')
    times = {
        hours: 336,
        days: 14,
        weeks: 2
    }
    convert_between = times.keys.reverse # [weeks, days, hours]
    # convert hours to weeks, days to days (should return without conversion), and weeks to hours
    times.each_with_index do |(unit, time_val), index|
      convert_unit = convert_between[index]
      converted_time = age_facet.convert_time_between_units(base_value: time_val, original_unit: unit, new_unit: convert_unit)
      expected_time = times[convert_unit]
      assert_equal expected_time, converted_time,
                   "Did not convert #{time_val} correctly from #{unit} to #{convert_unit}; expected #{expected_time} but found #{converted_time}"
    end

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end
end
