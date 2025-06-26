require 'test_helper'
require 'detached_helper'

class SearchFacetTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'SearchFacet Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)

    annotation_input = [
      { name: 'disease', type: 'group',
        values: %w[MONDO_0005109 MONDO_0018076 PATO_0000461 MONDO_0100096 MONDO_0005812] },
      { name: 'disease__ontology_label', type: 'group', values: [
        'HIV infectious disease', 'tuberculosis', 'normal', 'COVID-19', 'influenza'
      ] },
      { name: 'species', type: 'group',
        values: %w[NCBITaxon_9606 NCBITaxon_9606 NCBITaxon_10090 NCBITaxon_9606 NCBITaxon_10090] },
      { name: 'species__ontology_label', type: 'group', values: [
        'Homo sapiens', 'Homo sapiens', 'Mus musculus', 'Homo sapiens', 'Mus musculus'
      ] },
      { name: 'cell_type', type: 'group', values: %w[CL_0000236 CL_0000236 CL_0000561 CL_0000561 CL_0000573] },
      { name: 'cell_type__ontology_label', type: 'group',
        values: ['B cell', 'B cell', 'amacrine cell', 'amacrine cell', 'retinal cone cell'] },
      { name: 'library_preparation_protocol__ontology_label', type: 'group', values: Array.new(5, 'Seq-Well') },
      { name: 'organ__ontology_label', type: 'group', values: Array.new(5, 'milk') },
      { name: 'sex', type: 'group', values: Array.new(5, 'female') },
      { name: 'organism_age', type: 'numeric', values: [1, 3, 7, 12, 51] },
      { name: 'organism_age__unit_label', type: 'group', values: Array.new(5, 'year') }
    ]
    FactoryBot.create(:metadata_file, name: 'metadata.txt', study: @study, use_metadata_convention: true,
                      cell_input: %w[cellA cellB cellC cellD cellE], annotation_input:)
    TestDataPopulator.create_sample_search_facets
    @study.cell_metadata.find_by(name: 'organism_age', annotation_type: 'numeric').set_minmax_by_units!
    @search_facet = SearchFacet.find_by(identifier: 'species')
    @search_facet.update_filter_values!

    # filter_results to return from mock call to BigQuery
    @filter_results = [
      { id: 'NCBITaxon_9606', name: 'Homo sapiens' },
      { id: 'NCBITaxon_10090', name: 'Mus musculus' }
    ]

    SearchFacet.create(name: 'Cell type', identifier: 'cell_type', is_mongo_based: true,
                       ontology_urls: [
                         {
                           name: 'Cell Ontology',
                           url: 'https://www.ebi.ac.uk/ols/api/ontologies/cl',
                           browser_url: 'https://www.ebi.ac.uk/ols/ontologies/cl'
                         }
                       ],
                       data_type: 'string', is_ontology_based: true, is_array_based: false,
                       big_query_id_column: 'cell_type',
                       big_query_name_column: 'cell_type__ontology_label',
                       convention_name: 'Alexandria Metadata Convention', convention_version: '2.2.0')
  end

  after(:all) do
    FeatureFlag.destroy_all
    SearchFacet.destroy_all
  end

  # should return expected filters list
  # mocks call to BigQuery to avoid unnecessary overhead
  test 'should update filters list' do
    filters = @search_facet.get_unique_filter_values
    assert_equal @filter_results, filters
  end

  # should validate search facet correctly, especially links to external ontologies
  test 'should validate search_facet including ontology urls' do
    assert @search_facet.valid?, "Testing search facet did not validate: #{@search_facet.errors.full_messages}"
    invalid_facet = SearchFacet.new
    assert_not invalid_facet.valid?, 'Did not correctly find validation errors on empty facet'
    expected_error_count = 8
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

  test 'should set minmax values for numeric facets' do
    age_facet = SearchFacet.find_by(identifier: 'organism_age')
    age_facet.update_filter_values!
    assert age_facet.must_convert?,
           "Did not correctly return true for must_convert? with conversion column: #{age_facet.big_query_conversion_column}"
    assert_equal 1, age_facet.min,
                 "Did not set minimum value; expected 1 but found #{age_facet.min}"
    assert_equal 51, age_facet.max,
                 "Did not set minimum value; expected 51 but found #{age_facet.max}"
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
    azul_diseases = AzulSearchService.get_all_facet_filters['disease']
    disease_facet = SearchFacet.find_by(identifier: 'disease')
    disease_facet.update_filter_values!(azul_diseases)
    disease_facet.reload
    assert disease_facet.filters_with_external.any?
    expected_diseases = [
      { id: 'PATO_0000461', name: 'normal' },
      { id: 'MONDO_0005109', name: 'HIV infectious disease' },
      { id: 'MONDO_0100096', name: 'COVID-19' }
    ]
    expected_diseases.each do |filter|
      assert_includes disease_facet.filters_with_external, filter.with_indifferent_access
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
    azul_diseases = AzulSearchService.get_all_facet_filters['disease']
    disease_keyword = 'cancer'
    skip 'Azul search service not available' unless azul_diseases
    cancers = azul_diseases[:filters].select { |d| d.match?(disease_keyword) }
    disease_facet = SearchFacet.find_by(identifier: 'disease')
    disease_facet.update_filter_values!(azul_diseases)
    disease_facet.reload
    assert_empty disease_facet.find_filter_matches(disease_keyword)
    assert_equal cancers.sort,
                 disease_facet.find_filter_matches(disease_keyword, filter_list: :filters_with_external).sort
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

  test 'should find associated metadata and get unique filter values' do
    user = FactoryBot.create(:user, test_array: @@users_to_clean)
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Search facet associated metadata test',
                              public: true,
                              user:,
                              test_array: @@studies_to_clean)
    FactoryBot.create(:metadata_file,
                      name: 'metadata.txt',
                      study:,
                      use_metadata_convention: true,
                      annotation_input: [
                        {
                          name: 'cell_type',
                          type: 'group',
                          values: %w[CL_0000236 CL_0000561 CL_0000573]
                        },
                        {
                          name: 'cell_type__ontology_label',
                          type: 'group',
                          values: [
                            'B cell', 'amacrine cell', 'retinal cone cell'
                          ]
                        }
                      ])
    facet = SearchFacet.find_by(identifier: 'cell_type')
    expected_filters = [
      { id: 'CL_0000236', name: 'B cell' },
      { id: 'CL_0000561', name: 'amacrine cell' },
      { id: 'CL_0000573', name: 'retinal cone cell' }
    ]
    values = expected_filters.map { |f| [f[:id], f[:name]] }.flatten
    mock_query_not_detached [study] do
      facet.reload
      assert_equal expected_filters, facet.get_unique_filter_values(public_only: true)
      metadata_ids = CellMetadatum.where(name: 'cell_type').pluck(:id)
      assert_equal metadata_ids, facet.associated_metadata(values:).pluck(:id)
    end
  end

  test 'should get presence-based filters' do
    identifier = 'has_morphology'
    name = 'Has morphology'
    facet = SearchFacet.create(
      name:, identifier:, is_presence_facet: true, is_mongo_based: true, big_query_name_column: 'bil_url',
      big_query_id_column: 'bil_url', data_type: 'string', convention_name: 'Alexandria Metadata Convention',
      convention_version: '2.2.0'
    )
    expected_filter = [{ id: identifier, name: }.with_indifferent_access]
    assert_equal expected_filter, facet.filter_for_presence
    facet.update_filter_values!
    facet.reload
    assert_equal expected_filter, facet.filter_for_presence
  end

  test 'should sort and uniquify filters properly' do
    facet = SearchFacet.find_by(identifier: 'cell_type')
    facet.update_filter_values!
    assert facet.filters.first[:name] == 'amacrine cell'
    external_filters = { filters: ['b cell', 'B cell', 'amacrine cell', 'Amacrine Cell', 'T cell'] }
    facet.update_filter_values!(external_filters)
    facet.reload
    assert_equal 1, facet.filters_with_external.select { |f| f[:name] == 'amacrine cell' }.count
    assert_equal 1, facet.filters_with_external.select { |f| f[:name] == 'T cell' }.count
    assert_equal 'T cell', facet.filters_with_external.last[:name]
  end

  test 'should skip metadata if ids or values blank when getting unique filters' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Search facet empty metadata test',
                              public: true,
                              user: @user,
                              test_array: @@studies_to_clean)
    FactoryBot.create(:metadata_file,
                      name: 'metadata.txt',
                      study:,
                      use_metadata_convention: true,
                      annotation_input: [
                        { name: 'cell_type', type: 'group', values: %w[CL_0000236 CL_0000561 CL_0000573] }
                      ])
    metadatum = study.cell_metadata.find_by(name: 'cell_type')
    facet = SearchFacet.find_by(identifier: 'cell_type')
    assert_empty facet.filters_from_metadatum(metadatum)
    facet.update_filter_values! # should not raise an error
    assert facet.filters.any?
  end
end
