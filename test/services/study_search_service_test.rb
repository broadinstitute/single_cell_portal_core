require 'test_helper'

class StudySearchServiceTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @metadata_study = FactoryBot.create(:detached_study,
                                        name_prefix: 'Study Search Service Test',
                                        public: true,
                                        user: @user,
                                        test_array: @@studies_to_clean)
    @metadata_file = FactoryBot.create(:metadata_file,
                                       name: 'metadata.txt',
                                       study: @metadata_study,
                                       annotation_input: [
                                         {
                                           name: 'cell_type',
                                           type: 'group',
                                           values: [
                                             'B cell', 'amacrine cell', 'retinal cone cell'
                                           ]
                                         }
                                       ])
    @name_study = FactoryBot.create(:detached_study,
                                    name_prefix: 'Cell Name Test',
                                    public: false,
                                    user: @user,
                                    test_array: @@studies_to_clean)
    @base_studies = Study.where(user: @user)
    @filters = [
      { id: 'CL_0000236', name: 'B cell' },
      { id: 'CL_0000561', name: 'amacrine cell' },
      { id: 'CL_0000573', name: 'retinal cone cell' },
      { id: 'CL_0000103', name: 'bipolar neuron' }
    ]
    @search_facet = SearchFacet.create(name: 'Cell type', identifier: 'cell_type',
                                       filters: @filters,
                                       public_filters: @filters,
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

  test 'should generate query for keyword search' do
    terms = 'cell'
    query = StudySearchService.generate_mongo_query_by_context(terms: terms, base_studies: @base_studies,
                                                               accessions: [], query_context: :keyword)
    %i[studies metadata_matches results_matched_by_data].each do |key_name|
      assert query.keys.include?(key_name)
    end
    found_studies = query[:studies].pluck(:accession).sort
    assert_equal @base_studies.pluck(:accession).sort, found_studies
    assert_equal 1, query[:results_matched_by_data]['numResults:scp:metadata'.to_sym]
    metadata_accession = @metadata_study.accession
    assert query[:metadata_matches].keys == [metadata_accession]
    expected_filters = [
      { id: 'B cell', name: 'B cell' }.with_indifferent_access,
      { id: 'amacrine cell', name: 'amacrine cell' }.with_indifferent_access,
      { id: 'retinal cone cell', name: 'retinal cone cell' }.with_indifferent_access
    ]
    assert_equal expected_filters, query[:metadata_matches][metadata_accession][:cell_type]
  end

  test 'should generate query for phrase search' do
    terms = ['amacrine cell']
    query = StudySearchService.generate_mongo_query_by_context(terms: terms, base_studies: @base_studies,
                                                               accessions: [], query_context: :phrase)
    %i[studies metadata_matches results_matched_by_data].each do |key_name|
      assert query.keys.include?(key_name)
    end
    found_studies = query[:studies].pluck(:accession)
    assert_equal 1, query[:results_matched_by_data]['numResults:scp:metadata'.to_sym]
    metadata_accession = @metadata_study.accession
    assert_equal [metadata_accession], found_studies
    assert query[:metadata_matches].keys == [metadata_accession]
    expected_filters = [
      { id: 'amacrine cell', name: 'amacrine cell' }.with_indifferent_access,
    ]
    assert_equal expected_filters, query[:metadata_matches][metadata_accession][:cell_type]
  end

  test 'should generate query for accession-based search' do
    accessions = [@name_study.accession]
    query = StudySearchService.generate_mongo_query_by_context(terms: '', base_studies: @base_studies,
                                                               accessions: accessions, query_context: '')
    found_studies = query[:studies].pluck(:accession)
    assert_equal accessions, found_studies
  end

  test 'should find studies by converting keyword search' do
    matched_studies = StudySearchService.get_studies_from_term_conversion(['cell'])
    assert matched_studies[@metadata_study.accession].present?
    expected_results = @filters.map { |filter| filter[:name] }.select { |f| f =~ /cell/ }
    assert_equal expected_results, matched_studies[@metadata_study.accession][:cell_type].map { |f| f[:name] }
  end

  test 'should match facet filters from terms' do
    cell_matches = StudySearchService.match_facet_filters_from_terms(%w[cell])
    expected_filters = @filters.map { |filter| filter[:name] }.select { |f| f =~ /cell/ }
    expected_match = { cell_type: expected_filters }.with_indifferent_access
    assert_equal expected_match, cell_matches
    amacrine_match = StudySearchService.match_facet_filters_from_terms(%w[amacrine])
    expected_match = { cell_type: ['amacrine cell'] }.with_indifferent_access
    assert_equal expected_match, amacrine_match
    empty_match = StudySearchService.match_facet_filters_from_terms(%w[foo])
    assert_empty empty_match
  end

  test 'should escape terms via regexp' do
    terms = %w[foo bar baz]
    normal_terms = /(foo|bar|baz)/i
    assert_equal normal_terms, StudySearchService.escape_terms_for_regex(term_list: terms)
    quoted_terms = /(this\ is\ a\ whole\ phrase|foo|bar)/i
    assert_equal quoted_terms, StudySearchService.escape_terms_for_regex(term_list: ['this is a whole phrase', 'foo', 'bar'])
    terms_with_escapes = %w[foo foo$ foo. foo/]
    expected_escapes = /(foo|foo\$|foo\.|foo\/)/i
    assert_equal expected_escapes, StudySearchService.escape_terms_for_regex(term_list: terms_with_escapes)
  end
end
