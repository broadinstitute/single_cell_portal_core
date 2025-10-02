require 'api_test_helper'
require 'user_tokens_helper'
require 'bulk_download_helper'
require 'test_helper'
require 'includes_helper'

class SearchControllerTest < ActionDispatch::IntegrationTest

  HOMO_SAPIENS_FILTER = { id: 'NCBITaxon_9606', name: 'Homo sapiens' }.freeze
  NO_DISEASE_FILTER = { id: 'MONDO_0000001', name: 'disease or disorder' }.freeze

  # shorthand accessors
  FACET_DELIM = Api::V1::SearchController::FACET_DELIMITER
  FILTER_DELIM = Api::V1::SearchController::FILTER_DELIMITER

  before(:all) do
    # make sure all studies/users have been removed as dangling references can sometimes cause false negatives/failures
    StudyCleanupTools.destroy_all_studies_and_workspaces
    User.destroy_all
    @random_seed = SecureRandom.uuid
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @other_user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: "Search Testing Study #{@random_seed}",
                               public: true,
                               user: @user,
                               initialized: true,
                               test_array: @@studies_to_clean)
    @author = FactoryBot.create(:author, study: @study, last_name: 'Doe', first_name: 'john', institution: 'MIT')
    # add top-level metadata for results
    annotation_input = [
      { name: 'disease', type: 'group', values: Array.new(5, 'MONDO_0000001') },
      { name: 'disease__ontology_label', type: 'group', values: Array.new(5, 'disease or disorder') },
      { name: 'species', type: 'group', values: Array.new(5, 'NCBITaxon_9606') },
      { name: 'species__ontology_label', type: 'group', values: Array.new(5, 'Homo sapiens') },
      { name: 'library_preparation_protocol__ontology_label', type: 'group', values: Array.new(5, 'Seq-Well') },
      { name: 'organ__ontology_label', type: 'group', values: Array.new(5, 'milk') },
      { name: 'sex', type: 'group', values: Array.new(5, 'female') },
      { name: 'organism_age', type: 'numeric', values: [1, 3, 7, 12, 51] },
      { name: 'organism_age__unit_label', type: 'group', values: Array.new(5, 'year') }
    ]
    FactoryBot.create(:metadata_file, name: 'metadata.txt', study: @study, use_metadata_convention: true,
                      cell_input: %w[cellA cellB cellC cellD cellE],
                      annotation_input: )
    FactoryBot.create(:cluster_file, name: 'cluster_example.txt', study: @study)
    @other_study = FactoryBot.create(:detached_study,
                                     name_prefix: "API Test Study #{@random_seed}",
                                     public: true,
                                     user: @other_user,
                                     initialized: false,
                                     test_array: @@studies_to_clean)
    [@study, @other_study].each do |study|
      detail = study.build_study_detail
      detail.full_description = '<p>This is the description.</p>'
      detail.save!
    end
    TestDataPopulator.create_sample_search_facets
    @preset_search = PresetSearch.create!(name: 'Test Search', search_terms: ["Testing Study #{@random_seed}"],
                                          accession_list: [@study.accession])
  end

  setup do
    sign_in_and_update @user
    @convention_accessions = StudyFile.any_of(
      { file_type: 'Metadata' }, { file_type: 'AnnData', 'ann_data_file_info.has_metadata' => true }
    ).where(use_metadata_convention: true).map { |f| f.study.accession }.flatten
  end

  # reset known commonly used objects to initial states to prevent failures breaking other tests
  teardown do
    # Study.where(name: /Search Promotion Test/).destroy_all
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    reset_user_tokens
    @other_study.study_detail.update!(full_description: '')
    @other_study.update(public: true)
  end

  after(:all) do
    BrandingGroup.destroy_all
    SearchFacet.destroy_all
    PresetSearch.destroy_all
  end

  test 'should get all search facets' do
    facet_count = SearchFacet.visible.count
    execute_http_request(:get, api_v1_search_facets_path)
    assert_response :success
    assert json.size == facet_count, "Did not find correct number of search facets, expected #{facet_count} but found #{json.size}"
  end

  test 'should get visible search facets' do
    # make one random facet not visible
    invisible_facet = SearchFacet.all.sample
    invisible_facet.update!(visible: false)
    visible_count = SearchFacet.visible.count
    execute_http_request(:get, api_v1_search_facets_path)
    assert_response :success
    assert json.size == visible_count,
           "Did not find correct number of visible search facets, expected #{visible_count} but found #{json.size}"
    assert visible_count == SearchFacet.count - 1,
           "Did not return correct direct count of visible facets; #{visible_count} != #{SearchFacet.count - 1}"
    invisible_facet.update!(visible: true)
  end

  test 'should get search facets for branding group' do
    branding_group = FactoryBot.create(:branding_group, user_list: [@user])
    facet_list = SearchFacet.pluck(:identifier).take(2).sort
    branding_group.update!(facet_list: facet_list)
    execute_http_request(:get, api_v1_search_facets_path(scpbr: branding_group.name_as_id))
    assert_response :success
    response_facets = json.map {|entry| entry['id']}.sort
    assert response_facets == facet_list,
           "Did not find correct facets for #{branding_group.name_as_id}, expected #{facet_list} but found #{response_facets}"
    branding_group.update!(facet_list: [])
  end

  test 'should search facet filters' do
    @search_facet = SearchFacet.first
    @search_facet.update_filter_values!
    filter = @search_facet.filters.first
    valid_query = filter[:name]
    execute_http_request(:get, api_v1_search_facet_filters_path(facet: @search_facet.identifier, query: valid_query))
    assert_response :success
    assert_equal json['query'], valid_query, "Did not search on correct value; expected #{valid_query} but found #{json['query']}"
    assert_equal json['filters'].first, filter, "Did not find expected filter of #{filter} in response: #{json['filters']}"
    invalid_query = 'does not exist'
    execute_http_request(:get, api_v1_search_facet_filters_path(facet: @search_facet.identifier, query: invalid_query))
    assert_response :success
    assert_equal json['query'], invalid_query, "Did not search on correct value; expected #{invalid_query} but found #{json['query']}"
    assert_equal json['filters'].size, 0, "Should have found no filters; expected 0 but found #{json['filters'].size}"
  end

  test 'should return viewable studies on empty search' do
    execute_http_request(:get, api_v1_search_path(type: 'study'))
    assert_response :success
    expected_studies = Study.viewable(@user).pluck(:accession).sort
    found_studies = json['matching_accessions'].sort
    assert_equal expected_studies, found_studies, "Did not return correct studies; expected #{expected_studies} but found #{found_studies}"

    sign_out @user
    execute_http_request(:get, api_v1_search_path(type: 'study'))
    assert_response :success
    expected_studies = Study.viewable(nil).pluck(:accession).sort
    public_studies = json['matching_accessions'].sort
    assert_equal expected_studies, public_studies, "Did not return correct studies; expected #{expected_studies} but found #{public_studies}"
  end

  test 'should return search results using facets' do
    other_matches = Study.viewable(@user).any_of({ description: /#{HOMO_SAPIENS_FILTER[:name]}/ },
                                                 { description: /#{NO_DISEASE_FILTER[:name]}/ }).pluck(:accession)
    # find all human studies from metadata
    facet_query = "species:#{HOMO_SAPIENS_FILTER[:id]}#{FACET_DELIM}disease:#{NO_DISEASE_FILTER[:id]}"
    execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
    assert_response :success
    expected_accessions = (@convention_accessions + other_matches).uniq
    matching_accessions = json['matching_accessions']
    assert_equal expected_accessions, matching_accessions,
                 "Did not return correct array of matching accessions, expected #{expected_accessions} but found #{matching_accessions}"
    study_count = json['studies'].size
    assert_equal study_count, expected_accessions.size,
                 "Did not find correct number of studies, expected #{expected_accessions.size} but found #{study_count}"
    result_accession = json['studies'].first['accession']
    assert_equal result_accession, @study.accession, "Did not find correct study; expected #{@study.accession} but found #{result_accession}"
    matched_facets = json['studies'].first['facet_matches'].keys.sort
    matched_facets.delete_if {|facet| facet == 'facet_search_weight'} # remove search weight as it is not relevant

    source_facets = %w(disease species)
    assert_equal source_facets, matched_facets, "Did not match on correct facets; expected #{source_facets} but found #{matched_facets}"

    # check top-level metadata results
    source_study = Study.find_by(accession: result_accession)
    result_study = json['studies'].first
    source_study.cell_metadata.where(:name.in => Api::V1::StudySearchResultsObjects::COHORT_METADATA).each do |meta|
      truncated_name = meta.name.chomp('__ontology_label')
      assert_equal meta.values, result_study.dig('metadata', truncated_name)
    end
  end

  test 'should not query azul when collection is present' do
    branding_group = FactoryBot.create(:branding_group, user_list: [@user])
    terms = 'COVID-19'
    mock = Minitest::Mock.new
    mock.expect(:get_results, {}, [[], [terms]])
    AzulSearchService.stub(:append_results_to_studies, mock) do
      assert_raises MockExpectationError do
        execute_http_request(:get,
                             api_v1_search_path(
                               type: 'study',
                               terms: terms,
                               scpbr: branding_group.name_as_id
                             ))
        assert_response :success
        # this should raise a MockExpectationError as :get_results will not be called, as no Azul search was performed
        mock.verify
      end
    end
  end

  test 'should return search results using numeric facets' do
    CellMetadatum.where(name: 'organism_age').map(&:set_minmax_by_units!) # ensure minmax values are set
    facet = SearchFacet.find_by(identifier: 'organism_age')
    facet.update_filter_values! # in case there is a race condition with parsing & facet updates
    # loop through 3 different units (days, months, years) to run a numeric-based facet query with conversion
    # days should return nothing, but months and years should match the testing study
    %w(days months years).each do |unit|
      facet_query = "#{facet.identifier}:#{facet.min + 1}#{FILTER_DELIM}#{facet.max - 1}#{FILTER_DELIM}#{unit}"
      execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
      assert_response :success
      expected_accessions = unit == 'days' ? [] : @convention_accessions
      matching_accessions = json['matching_accessions']
      expected_accessions.each do |accession|
        assert_includes matching_accessions, accession,
                        "Facet query: #{facet_query} returned incorrect matches; expected #{expected_accessions} but found #{matching_accessions}"

      end
    end
  end

  test 'should return search results using keywords' do
    # test single keyword first
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: @random_seed))
    assert_response :success
    expected_accessions = Study.viewable(@user).where(name: /#{@random_seed}/).pluck(:accession).sort
    matching_accessions = json['matching_accessions'].sort # need to sort results since they are returned in weighted order
    assert_equal expected_accessions, matching_accessions,
                 "Did not return correct array of matching accessions, expected #{expected_accessions} but found #{matching_accessions}"

    assert_equal @random_seed, json['studies'].first['term_matches'].first
    assert_equal 2, json['match_by_data']['numResults:scp:text']

    # test exact phrase
    search_phrase = '"API Test Study"'
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: search_phrase))
    assert_response :success
    quoted_accessions = [@other_study.accession]
    found_accessions = json['matching_accessions'] # no need to sort as there should only be one result
    assert_equal quoted_accessions, found_accessions,
                 "Did not return correct array of matching accessions, expected #{quoted_accessions} but found #{found_accessions}"

    assert_equal search_phrase.gsub(/\"/, ''), json['studies'].first['term_matches'].first
    assert_equal 1, json['match_by_data']['numResults:scp:name']

    # test combination
    search_phrase += ' testing'
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: search_phrase))
    assert_response :success
    mixed_accessions = Study.any_of({ name: /API Test Study #{@random_seed}/ },
                                    { name: /testing/i }).pluck(:accession).sort
    found_mixed_accessions = json['matching_accessions'].sort
    assert_equal mixed_accessions, found_mixed_accessions,
                 "Did not return correct array of matching accessions, expected #{mixed_accessions} but found #{found_mixed_accessions}"
    assert_equal 'testing', json['studies'].first['term_matches'].first
    assert_equal 'API Test Study', json['studies'].last['term_matches'].first

    # test author keyword search for name
    search_terms = 'Doe'
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: search_terms))
    assert_response :success
    author_match_study_ids = Author.where(:$text => {:$search => search_terms}).pluck(:study_id)
    expected_accessions = Study.viewable(@user).where(:id.in => author_match_study_ids).pluck(:accession)
    matching_accessions = json['matching_accessions']
    assert_equal expected_accessions, matching_accessions,
                  "Did not return correct array of matching accessions, expected #{expected_accessions} but found #{matching_accessions}"

    assert_equal search_terms, json['studies'].first['term_matches'].first
    assert_equal 1, json['match_by_data']['numResults:scp:author']

    # test author keyword search for institution
    search_terms = 'MIT'
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: search_terms))
    assert_response :success
    author_match_study_ids = Author.where(:$text => {:$search => search_terms}).pluck(:study_id)
    expected_accessions = Study.viewable(@user).where(:id.in => author_match_study_ids).pluck(:accession)
    matching_accessions = json['matching_accessions']
    assert_equal expected_accessions, matching_accessions,
                  "Did not return correct array of matching accessions, expected #{expected_accessions} but found #{matching_accessions}"

    assert_equal search_terms, json['studies'].first['term_matches'].first
    assert_equal 1, json['match_by_data']['numResults:scp:author']

    # test regex escaping
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: 'foobar scp-105 [('))
    assert_response :success
  end

  test 'should return search results using accessions' do
    # test single accession
    term = Study.where(public: true).first.accession
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: term))
    assert_response :success
    expected_accessions = [term]
    assert_equal expected_accessions, json['matching_accessions'],
                 "Did not return correct array of matching accessions, expected #{expected_accessions} but found #{json['matching_accessions']}"
  end

  test 'should filter search results by branding group' do
    # add study to branding group and search - should get 1 result
    branding_group = FactoryBot.create(:branding_group, user_list: [@user])
    @study.update(branding_group_ids: [branding_group.id])

    query_parameters = {type: 'study', terms: @random_seed, scpbr: branding_group.name_as_id}
    execute_http_request(:get, api_v1_search_path(query_parameters))
    assert_response :success
    result_count = json['studies'].size
    assert_equal 1, result_count, "Did not find correct number of studies, expected 1 but found #{result_count}"
    found_study = json['studies'].first
    assert found_study['study_url'].include?("scpbr=#{branding_group.name_as_id}"),
           "Did not append branding group identifier to end of study URL: #{found_study['study_url']}"

    # remove study from group and search again - should get 0 results
    @study.update(branding_group_ids: [])
    execute_http_request(:get, api_v1_search_path(query_parameters))
    assert_response :success
    assert_empty json['studies'], "Did not find correct number of studies, expected 0 but found #{json['studies'].size}"
  end

  test 'should run inferred search using facets' do
    @other_study.study_detail.update(full_description: '')
    facet_query = "species:#{HOMO_SAPIENS_FILTER[:id]}"
    execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
    assert_response :success
    expected_accessions = @convention_accessions
    expected_accessions.each do |accession|
      assert_includes json['matching_accessions'], accession,
                      "Did not find expected accessions before inferred search, expected #{expected_accessions} but found #{json['matching_accessions']}"

    end
    # now update non-convention study to include a filter display value in its description
    # this should be picked up by the "inferred" search
    @other_study.study_detail.update(full_description: HOMO_SAPIENS_FILTER[:name])
    execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
    assert_response :success
    inferred_accessions = expected_accessions + [@other_study.accession]
    inferred_accessions.each do |accession|
      assert_includes json['matching_accessions'], accession,
                      "Did not find expected accessions after inferred search, expected #{inferred_accessions} but found #{json['matching_accessions']}"
    end
    assert_equal @other_study.accession, json['matching_accessions'].last
           "Did not mark last search results as inferred_match: #{json['matching_accessions'].last} != #{@other_study.accession}"
  end

  test 'should run inferred search using facets and phrase' do
    facet_query = "species:#{HOMO_SAPIENS_FILTER[:id]}"
    @other_study.study_detail.update(full_description: HOMO_SAPIENS_FILTER[:name])
    search_phrase = "Study #{@random_seed}"
    expected_accessions = (@convention_accessions + [@other_study.accession]).uniq
    execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query, terms: "\"#{search_phrase}\""))
    assert_response :success
    found_accessions = json['matching_accessions']
    assert_equal expected_accessions, found_accessions,
                 "Did not find expected accessions for phrase & facet search, expected #{expected_accessions} but found #{found_accessions}"
    # the combination of phrase + facet search is an AND, so 'API Test Study' will still be inferred as it does not
    # meet both search criteria
    non_inferred_study = json['studies'].first
    inferred_study = json['studies'].last
    assert_not non_inferred_study['inferred_match'],
               "First search result #{non_inferred_study['accession']} incorrectly marked as inferred"
    assert inferred_study['inferred_match'],
           "Last search result #{inferred_study['accession']} was not marked inferred"
    json['studies'].each do |study|
      assert_includes study['term_matches'], search_phrase,
                      "Did not find #{search_phrase} in term_matches for #{study['accession']}: #{study['term_matches']}"
    end
  end

  test 'should find intersection of facets on inferred search' do
    # update other_study to match one filter from facets; should not be inferred since it doesn't meet both criteria
    facet_query = "species:#{HOMO_SAPIENS_FILTER[:id]}#{FACET_DELIM}disease:#{NO_DISEASE_FILTER[:id]}"
    @other_study.study_detail.update(full_description: HOMO_SAPIENS_FILTER[:name])
    execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
    assert_response :success
    assert_equal @convention_accessions, json['matching_accessions'],
                 "Did not find expected accessions before inferred search, expected #{@convention_accessions} but found #{json['matching_accessions']}"

    # update to match both filters; should be inferred
    double_facet_name = "#{HOMO_SAPIENS_FILTER[:name]} #{NO_DISEASE_FILTER[:name]}"
    @other_study.study_detail.update(full_description: double_facet_name)
    execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
    assert_response :success
    inferred_accessions = @convention_accessions + [@other_study.accession]
    assert_equal inferred_accessions, json['matching_accessions'],
                 "Did not find expected accessions after inferred search, expected #{inferred_accessions} but found #{json['matching_accessions']}"
    inferred_study = json['studies'].last
    assert inferred_study['inferred_match'], "Did not correctly mark #{@other_study.accession} as inferred"
  end

  test 'should run preset search' do
    # run accession list only search
    execute_http_request(:get, api_v1_search_path(type: 'study', preset_search: @preset_search.identifier))
    assert_response :success
    permitted_accessions = [@study.accession]
    assert json['matching_accessions'] == permitted_accessions,
           "Did not return correct permitted studies for preset search; expected #{permitted_accessions} but found #{json['matching_accessions']}"
    found_preset = json['studies'].first
    assert found_preset['accession'] == @study.accession
    assert found_preset['preset_match'], "Did not correctly mark permitted study as preset match; #{found_preset['preset_match']}"

    # update to use user-search terms as well, include all studies to widen search
    all_accessions = Study.pluck(:accession)
    @preset_search.update(accession_list: all_accessions, search_terms: [])
    @preset_search.reload
    search_terms = '"API Test Study"'
    execute_http_request(:get, api_v1_search_path(type: 'study', preset_search: @preset_search.identifier, terms: search_terms))
    assert_response :success
    assert_equal 1, json['studies'].count, "Found wrong number of studies; should be 1 but found #{json['studies'].count}"
    expected_results = [@other_study.accession]
    assert_equal expected_results, json['matching_accessions'],
                 "Found wrong study with keywords & preset search; expected #{expected_results} but found #{json['matching_accessions']}"
    found_study = json['studies'].first
    assert found_study['preset_match']
    assert_equal ['API Test Study'], found_study['term_matches'], "Did not correctly match on #{search_terms}: #{found_study['term_matches']}"
    # run search using facet filters, which should only get data from BigQuery
    @preset_search.update(facet_filters: ['species:NCBITaxon_9606', 'disease:MONDO_0000001'], search_terms: [@random_seed])
    @preset_search.reload
    execute_http_request(:get, api_v1_search_path(type: 'study', preset_search: @preset_search.identifier, terms: ''))
    assert_response :success
    expected_results = [@study.accession]
    assert_equal 1, json['studies'].count, "Found wrong number of studies; should be 1 but found #{json['studies'].count}"
    assert_equal expected_results, json['matching_accessions'],
                 "Found wrong study with keywords & preset search; expected #{expected_results} but found #{json['matching_accessions']}"
  end

  test 'should log out user after inactivity' do
    # save access token to prevent breaking downstream tests
    valid_token = @user.api_access_token.dup
    # mark study as false to show if a user is signed in or not
    api_test_study = Study.find_by(name: /API Test Study/)
    api_test_study.update(public: false)
    search_terms = '"API Test Study"'
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: search_terms))
    assert_response :success
    expected_results = [api_test_study.accession]
    assert_equal expected_results, json['matching_accessions'],
                 "Found wrong study with keywords search; expected #{expected_results} but found #{json['matching_accessions']}"
    # now simulate a user "timing out" by back-dating last_access_at timestamp by double the timeout threshold
    # and then re-run search
    last_access = @user.api_access_token[:last_access_at]
    timed_out_stamp = last_access - User.timeout_in * 2
    @user.api_access_token[:last_access_at] = timed_out_stamp
    @user.save
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: search_terms))
    assert_response :success
    accessions = json['matching_accessions']
    assert_empty accessions, "Did not successfully time out session, accessions were found: #{accessions}"
    # clean up
    api_test_study.update(public: true)
    @user.update(api_access_token: valid_token)
  end

  test 'should escape quotes in facet filter values' do
    sanitized_filter = Api::V1::SearchController.sanitize_filter_value("10X 3' v3")
    expected_value = "10X 3\\' v3"
    assert_equal expected_value, sanitized_filter
  end

  test 'should return study name exact match first without quotes' do
    studies = []
    5.times do
      studies << FactoryBot.create(:detached_study,
                                   name_prefix: "Search Promotion Test #{SecureRandom.uuid}",
                                   public: true,
                                   user: @user,
                                   initialized: false,
                                   test_array: @@studies_to_clean)
    end
    studies.each do |study|
      detail = study.build_study_detail
      detail.full_description = '<p>This is the description.</p>'
      detail.save!
    end
    study_name = studies.sample.name
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: study_name))
    assert_response :success
    assert_equal study_name, json['studies'].first['name']
  end

  test 'should reorder results for exact name match' do
    studies, match_data = Api::V1::SearchController.promote_exact_match(@other_study.name,
                                                                        [@study, @other_study],
                                                                        {})
    assert_equal @other_study.accession, studies.first.accession
    assert_equal 1, match_data.with_indifferent_access['numResults:scp:exactTitle']
  end

  test 'should return initialized studies first in empty search' do
    execute_http_request(:get, api_v1_search_path(type: 'study'))
    assert_response :success
    first_study = json['studies'].first['accession']
    assert_equal @study.accession, first_study
  end

  test 'should filter stop words from queries' do
    terms = %w[human mouse study data]
    filtered_terms = Api::V1::SearchController.reject_stop_words_from_terms(terms)
    assert_equal terms, filtered_terms
    stop_words = %w[in the about at on for]
    filtered_terms = Api::V1::SearchController.reject_stop_words_from_terms(stop_words)
    assert_empty filtered_terms
    mixed_query = terms + stop_words
    filtered_terms = Api::V1::SearchController.reject_stop_words_from_terms(mixed_query)
    assert_equal terms, filtered_terms
  end

  test 'should support all sorting options' do
    ['recent', 'popular', 'foo', nil].each do |sort_order|
      facet_query = "species:#{HOMO_SAPIENS_FILTER[:id]}"
      execute_http_request(:get,
                           api_v1_search_path(
                             type: 'study',
                             facets: facet_query,
                             order: sort_order.to_s
                           ))
      assert_response :success
    end
  end

  test 'should query Azul when requested' do
    facet_query = "species:#{HOMO_SAPIENS_FILTER[:id]}"
    species_facet = SearchFacet.find_by(identifier: 'species')
    facet = {
      id: species_facet.identifier,
      filters: [HOMO_SAPIENS_FILTER],
      db_facet: species_facet
    }
    mock = Minitest::Mock.new
    mock.expect(:get_results, {}, [[facet], []])
    AzulSearchService.stub(:append_results_to_studies, mock) do
      assert_raises MockExpectationError do
        execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
        assert_response :success
        mock.verify
      end
    end
    studies_by_facet = {
      @study.accession => {
        disease: [HOMO_SAPIENS_FILTER],
        facet_search_weight: 1
      }
    }.with_indifferent_access
    positive_mock = Minitest::Mock.new
    positive_mock.expect :[], [@study], [:studies]
    positive_mock.expect :[], studies_by_facet, [:facet_map]
    positive_mock.expect :[], {}, [:results_matched_by_data]
    AzulSearchService.stub(:append_results_to_studies, positive_mock) do
      execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query, external: 'hca'))
      assert_response :success
      positive_mock.verify
    end
  end

  test 'should return text results when requested' do
    other_matches = Study.viewable(@user).any_of({ description: /#{HOMO_SAPIENS_FILTER[:name]}/ },
                                                 { description: /#{NO_DISEASE_FILTER[:name]}/ }).pluck(:accession)
    facet_query = "species:#{HOMO_SAPIENS_FILTER[:id]}#{FACET_DELIM}disease:#{NO_DISEASE_FILTER[:id]}"
    execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query, export: 'tsv'))
    assert_response :success
    lines = json.split(/\n/)[1..]
    all_accessions = (@convention_accessions + other_matches.map(&:accession)).flatten.uniq.sort
    found_accessions = lines.map { |l| l.split(/\t/)[1] }.flatten.uniq.sort
    assert_equal all_accessions, found_accessions
  end

  test 'should find studies based on available data types' do
    search_study = FactoryBot.create(:detached_study,
                                     name_prefix: "Raw Counts Search Study #{@random_seed}",
                                     public: true,
                                     user: @user,
                                     test_array: @@studies_to_clean)
    detail = search_study.build_study_detail
    detail.full_description = '<p>This is the description.</p>'
    detail.save!
    cells = %w[cellA cellB cellC cellD cellE cellF cellG]
    FactoryBot.create(
      :metadata_file, name: 'metadata.txt', study: search_study, use_metadata_convention: true, cell_input: cells,
      annotation_input: [{ name: 'species', type: 'group', values: %w[dog cat dog dog cat cat cat] }]
    )
    coordinates = 1.upto(7).to_a
    cluster_file = FactoryBot.create(
      :cluster_file, name: 'cluster_diffexp.txt', study: search_study,
      cell_input: { x: coordinates, y: coordinates, cells: }
    )

    %w[raw_counts diff_exp spatial].each do |data_type|
      execute_http_request(:get, api_v1_search_path(type: 'study', data_types: data_type))
      assert_response :success
      assert_empty json['studies']
    end

    # create raw counts matrix
    exp_matrix = FactoryBot.create(:expression_file,
                                   name: 'matrix.tsv',
                                   study: search_study)
    exp_matrix.build_expression_file_info(
      is_raw_counts: true, units: 'raw counts', library_preparation_protocol: "10x 5' v3",
      modality: 'Transcriptomic: unbiased', biosample_input_type: 'Whole cell'
    )
    exp_matrix.save
    # create DE results
    DifferentialExpressionResult.create(
      study: search_study, cluster_group: cluster_file.cluster_groups.first, annotation_name: 'species',
      annotation_scope: 'study', matrix_file_id: exp_matrix.id
    )
    # create spatial cluster
    FactoryBot.create(
      :cluster_file, name: 'spatial.txt', study: search_study, is_spatial: true,
      cell_input: { x: coordinates, y: coordinates, cells: }
    )

    %w[raw_counts diff_exp spatial].each do |data_type|
      execute_http_request(:get, api_v1_search_path(type: 'study', data_types: data_type))
      assert_response :success
      assert_equal search_study.accession, json['studies'].first['accession']
    end
  end
end
