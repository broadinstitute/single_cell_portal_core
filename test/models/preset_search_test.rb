require 'test_helper'

class PresetSearchTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Testing Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    @preset_search = PresetSearch.create!(name: 'Test Search', search_terms: ["Testing Study"],
                                          facet_filters: ['species:NCBITaxon_9606', 'disease:MONDO_0000001'],
                                          accession_list: [@study.accession])
    TestDataPopulator.create_sample_search_facets
    @species_facet = SearchFacet.find_by(identifier: 'species')
    @disease_facet = SearchFacet.find_by(identifier: 'disease')
    @species_facet.update_filter_values!
    @disease_facet.update_filter_values!
    @matching_facets = [
      {
        id: 'species',
        filters: [{ "id" => "NCBITaxon_9606", "name" => "Homo sapiens" }],
        db_facet: @species_facet
      },
      {
        id: 'disease',
        filters: [{ "id" => "MONDO_0000001", "name" => "disease or disorder" } ],
        db_facet: @disease_facet
      }
    ]
  end

  after(:all) do
    PresetSearch.destroy_all
    SearchFacet.destroy_all
  end

  test 'should return correct keyword query string' do
    expected_query = "\"Testing Study\""
    assert expected_query == @preset_search.keyword_query_string,
           "Query string did not match: #{expected_query} != #{@preset_search.keyword_query_string}"
  end

  test 'should return correct facet query string' do
    expected_query = 'species:NCBITaxon_9606+disease:MONDO_0000001'
    assert expected_query == @preset_search.facet_query_string
  end

  test 'should return correct matching facets' do
    @sorted_facets = @matching_facets.sort_by { |facet| facet[:id] }
    @preset_search_facet_filters = @preset_search.matching_facets_and_filters.sort_by { |facet| facet[:id] }
    assert @sorted_facets == @preset_search_facet_filters,
           "Did not correctly match facets/filters; #{@sorted_facets} != #{@preset_search_facet_filters}"
    associated_facet = @preset_search.search_facets.detect { |facet| facet.identifier == 'species' }
    assert @species_facet == associated_facet
  end

  test 'should validate new preset search' do
    # create valid preset search
    @terms = ['test', "Study #{@random_seed}"]
    @filters = 'species:NCBITaxon_10090'
    @new_preset = PresetSearch.new(name: 'Another Search', search_terms: @terms, facet_filters: [@filters])
    assert @new_preset.valid?

    # create invalid preset search, test validations
    @invalid_preset = PresetSearch.new
    assert !@invalid_preset.valid?
    errors = @invalid_preset.errors
    expected_errors = [:name, :base]
    assert_equal expected_errors, errors.messages.keys,
                 "Did not find correct errors; should be #{expected_errors}, found #{errors.messages.keys}"

    # duplicate search terms
    @invalid_preset.name = 'New Search'
    @invalid_preset.search_terms = %w(test test)
    assert !@invalid_preset.valid?
    expected_error = 'Search terms contains duplicated values: test'
    found_error = @invalid_preset.errors.full_messages.first
    assert_equal expected_error, found_error, "Did not correctly find duplicated search term: #{found_error}"

    # duplicate facets
    @invalid_preset.search_terms = %w(test)
    invalid_filters = %w(disease:MONDO_0000001 disease:MONDO_0000001)
    @invalid_preset.facet_filters = invalid_filters
    assert !@invalid_preset.valid?
    expected_facet_error = 'Facet filters contains duplicated identifiers/filters: disease, MONDO_0000001'
    found_facet_error = @invalid_preset.errors.full_messages.first
    assert_equal expected_facet_error, found_facet_error,
                 "Did not correctly find duplicated facets: #{found_facet_error}"

    # non-existent studies in accession list
    @invalid_preset.facet_filters = %w(disease:MONDO_0000001)
    @invalid_preset.accession_list = %w(SCP0)
    assert !@invalid_preset.valid?
    expected_accession_error = 'Accession list contains missing studies: SCP0'
    found_accession_error = @invalid_preset.errors.full_messages.first
    assert_equal expected_accession_error, found_accession_error,
                 "Did not correctly find missing studies: #{found_accession_error}"
  end
end
