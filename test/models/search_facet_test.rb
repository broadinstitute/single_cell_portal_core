require 'test_helper'

class SearchFacetTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'SearchFacet Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    TestDataPopulator.create_sample_search_facets
    @search_facet = SearchFacet.find_by(identifier: 'species')
    @search_facet.update_filter_values!

    # filter_results to return from mock call to BigQuery
    @filter_results = [
      { id: 'NCBITaxon_9606', name: 'Homo sapiens' },
      { id: 'NCBITaxon_10090', name: 'Mus musculus' }
    ]

    # mock schema for number_of_reads column in BigQuery
    @column_schema = [{ column_name: 'number_of_reads', data_type: 'FLOAT64', is_nullable: 'YES' }]
    # mock minmax query for organism_age query
    @minmax_results = [{ MIN: rand(10) + 1, MAX: rand(100) + 10 }]
  end

  after(:all) do
    FeatureFlag.destroy_all
    SearchFacet.destroy_all
  end

  # should return expected filters list
  # mocks call to BigQuery to avoid unnecessary overhead
  test 'should update filters list' do
    # mock call to BQ, until a better library can be found
    mock = Minitest::Mock.new
    mock.expect :query, @filter_results, [String]

    SearchFacet.stub :big_query_dataset, mock do
      filters = @search_facet.get_unique_filter_values
      mock.verify
      assert_equal @filter_results, filters
    end
  end

  # should generate correct kind of query for DISTINCT filters based on array/non-array columns
  # generate_query_string_by_type should return the correct query string in each case, based on facet type
  test 'should generate correct distinct queries' do
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
  end

  test 'should generate correct distinct queries for public-only studies' do
    public_studies = Study.where(public: true).pluck(:accession)
    public_query = "study_accession IN (#{public_studies.map { |acc| "\'#{acc}\'" }.join(', ')})"
    non_array_query = @search_facet.generate_bq_query_string(accessions: public_studies)
    assert_match public_query, non_array_query, "Non-array query did not contain correct DISTINCT clause: #{non_array_query}"
    array_facet = SearchFacet.find_by(identifier: 'disease')
    array_query = array_facet.generate_bq_query_string(accessions: public_studies)
    assert_match public_query, array_query, "Array query did not correctly unnest column or match offset positions: #{array_query}"
  end

  # should validate search facet correctly, especially links to external ontologies
  test 'should validate search_facet including ontology urls' do
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
  end

  test 'should set data_type and is_array_based on create' do
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
  end

  test 'should set minmax values for numeric facets' do
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
  end

  test 'should convert time values between units' do
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
  end

  test 'should merge external facet filters when updating' do
    mock = Minitest::Mock.new
    filters = [
      { id: 'MONDO_0005109', name: 'HIV infectious disease' },
      { id: 'MONDO_0018076', name: 'tuberculosis' }
    ]
    mock.expect :query, filters, [String]
    azul_diseases = AzulSearchService.get_all_facet_filters['disease']
    SearchFacet.stub :big_query_dataset, mock do
      disease_facet = SearchFacet.find_by(identifier: 'disease')
      disease_facet.update_filter_values!(azul_diseases)
      mock.verify
      disease_facet.reload
      assert disease_facet.filters_with_external.any?
      expected_diseases = %w[normal COVID-19 influenza]
      expected_diseases.each do |disease_name|
        filter_value = { id: disease_name, name: disease_name }.with_indifferent_access
        assert_includes disease_facet.filters_with_external, filter_value
      end
    end
  end

  test 'should find matching filter value' do
    assert @search_facet.filters_include? 'Homo sapiens'
    assert_not @search_facet.filters_include? 'foobar'
  end

  test 'should return correct facet list for user' do
    user = FactoryBot.create(:user, test_array: @@users_to_clean)
    # don't save facet to prevent calling :update_filter_values!
    organ_facet = SearchFacet.new(
      identifier: 'organ',
      name: 'organ',
      filters: [
        { id: 'UBERON_0000178', name: 'blood' },
        { id: 'UBERON_0000955', name: 'brain' }
      ],
      public_filters: [
        { id: 'UBERON_0000955', name: 'brain' }
      ],
      filters_with_external: [
        { id: 'UBERON_0000178', name: 'blood' },
        { id: 'UBERON_0000955', name: 'brain' },
        { id: 'heart', name: 'heart' }
      ]
    )
    assert_equal organ_facet.public_filters, organ_facet.filters_for_user(nil)
    assert_equal organ_facet.filters_with_external, organ_facet.filters_for_user(user)
  end

  test 'should flatten filter list' do
    @search_facet.filters = @filter_results
    expected_filters = @filter_results.map { |f| [f[:id], f[:name]] }.flatten
    assert_equal expected_filters, @search_facet.flatten_filters
  end

  test 'should find all filter matches' do
    mock = Minitest::Mock.new
    filters = [
      { id: 'MONDO_0005109', name: 'HIV infectious disease' },
      { id: 'MONDO_0018076', name: 'tuberculosis' }
    ]
    mock.expect :query, filters, [String]
    azul_diseases = AzulSearchService.get_all_facet_filters['disease']
    disease_keyword = 'cancer'
    cancers = azul_diseases[:filters].select { |d| d.match?(disease_keyword) }
    SearchFacet.stub :big_query_dataset, mock do
      disease_facet = SearchFacet.find_by(identifier: 'disease')
      disease_facet.update_filter_values!(azul_diseases)
      mock.verify
      disease_facet.reload
      assert_empty disease_facet.find_filter_matches(disease_keyword)
      assert_equal cancers.sort,
                   disease_facet.find_filter_matches(disease_keyword, filter_list: :filters_with_external).sort
    end
  end

  test 'should determine if a filter matches' do
    organ_facet = SearchFacet.new(
      identifier: 'organ',
      name: 'organ',
      filters: [
        { id: 'UBERON_0000178', name: 'blood' },
        { id: 'UBERON_0000955', name: 'brain' }
      ],
      public_filters: [
        { id: 'UBERON_0000955', name: 'brain' }
      ],
      filters_with_external: [
        { id: 'UBERON_0000178', name: 'blood' },
        { id: 'UBERON_0000955', name: 'brain' },
        { id: 'heart', name: 'heart' }
      ]
    )
    assert organ_facet.filters_match?('blood')
    assert_not organ_facet.filters_match?('heart')
    assert_not organ_facet.filters_match?('foo')
    assert organ_facet.filters_match?('heart', filter_list: :filters_with_external)
  end
end
