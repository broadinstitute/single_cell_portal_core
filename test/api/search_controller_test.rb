require 'api_test_helper'

class SearchControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include Requests::JsonHelpers
  include Requests::HttpHelpers

  HOMO_SAPIENS_FILTER = { id: 'NCBITaxon_9606', name: 'Homo sapiens' }
  NO_DISEASE_FILTER = { id: 'MONDO_0000001', name: 'disease or disorder' }

  setup do
    @user = User.find_by(email: 'testing.user.2@gmail.com')
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
                                                                           :provider => 'google_oauth2',
                                                                           :uid => '123545',
                                                                           :email => 'testing.user@gmail.com'
                                                                       })
    sign_in @user
    @random_seed = File.open(Rails.root.join('.random_seed')).read.strip
    @user.update_last_access_at! # ensure user is marked as active
  end

  test 'should get all search facets' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    facet_count = SearchFacet.visible.count
    execute_http_request(:get, api_v1_search_facets_path)
    assert_response :success
    assert json.size == facet_count, "Did not find correct number of search facets, expected #{facet_count} but found #{json.size}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should get visible search facets' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

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

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should get search facets for branding group' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    branding_group = BrandingGroup.first
    facet_list = SearchFacet.pluck(:identifier).take(2).sort
    branding_group.update!(facet_list: facet_list)
    execute_http_request(:get, api_v1_search_facets_path(scpbr: branding_group.name_as_id))
    assert_response :success
    response_facets = json.map {|entry| entry['id']}.sort
    assert response_facets == facet_list,
           "Did not find correct facets for #{branding_group.name_as_id}, expected #{facet_list} but found #{response_facets}"
    branding_group.update!(facet_list: [])

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should search facet filters' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    @search_facet = SearchFacet.first
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

    puts "#{File.basename(__FILE__)}: #{self.method_name} completed!"
  end

  test 'should return viewable studies on empty search' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

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

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should return search results using facets' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    study = Study.find_by(name: "Test Study #{@random_seed}")
    facets = SearchFacet.where(data_type: 'string')

    # find all human studies from metadata
    facet_query = "species:#{HOMO_SAPIENS_FILTER[:id]}+disease:#{NO_DISEASE_FILTER[:id]}"
    execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
    assert_response :success
    expected_accessions = [study.accession]
    matching_accessions = json['matching_accessions']
    assert_equal expected_accessions, matching_accessions,
                 "Did not return correct array of matching accessions, expected #{expected_accessions} but found #{matching_accessions}"
    study_count = json['studies'].size
    assert_equal study_count, 1, "Did not find correct number of studies, expected 1 but found #{study_count}"
    result_accession = json['studies'].first['accession']
    assert_equal result_accession, study.accession, "Did not find correct study; expected #{study.accession} but found #{result_accession}"
    matched_facets = json['studies'].first['facet_matches'].keys.sort
    matched_facets.delete_if {|facet| facet == 'facet_search_weight'} # remove search weight as it is not relevant
    source_facets = facets.map(&:identifier).sort
    assert_equal source_facets, matched_facets, "Did not match on correct facets; expected #{source_facets} but found #{matched_facets}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should return search results using numeric facets' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    study = Study.find_by(name: "Test Study #{@random_seed}")
    facet = SearchFacet.find_by(identifier: 'organism_age')
    facet.update_filter_values! # in case there is a race condition with parsing & facet updates
    # loop through 3 different units (days, months, years) to run a numeric-based facet query with conversion
    # days should return nothing, but months and years should match the testing study
    %w(days months years).each do |unit|
      facet_query = "#{facet.identifier}:#{facet.min + 1},#{facet.max - 1},#{unit}"
      execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
      assert_response :success
      expected_accessions = unit == 'days' ? [] : [study.accession]
      matching_accessions = json['matching_accessions']
      assert_equal expected_accessions, matching_accessions,
                   "Facet query: #{facet_query} returned incorrect matches; expected #{expected_accessions} but found #{matching_accessions}"
    end

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should return search results using keywords' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # test single keyword first
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: @random_seed))
    assert_response :success
    expected_accessions = Study.pluck(:accession)
    matching_accessions = json['matching_accessions'].sort # need to sort results since they are returned in weighted order
    assert_equal expected_accessions, matching_accessions,
                 "Did not return correct array of matching accessions, expected #{expected_accessions} but found #{matching_accessions}"

    assert_equal @random_seed, json['studies'].first['term_matches'].first

    # test exact phrase
    search_phrase = "\"API Test Study\""
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: search_phrase))
    assert_response :success
    quoted_accessions = Study.where(name: "API Test Study #{@random_seed}").pluck(:accession)
    found_accessions = json['matching_accessions'] # no need to sort as there should only be one result
    assert_equal quoted_accessions, found_accessions,
                 "Did not return correct array of matching accessions, expected #{quoted_accessions} but found #{found_accessions}"

    assert_equal search_phrase.gsub(/\"/, ''), json['studies'].first['term_matches'].first

    # test combination
    search_phrase += " testing"
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: search_phrase))
    assert_response :success
    mixed_accessions = Study.any_of({name: "API Test Study #{@random_seed}"},
                                       {name: "Testing Study #{@random_seed}"}).pluck(:accession).sort
    found_mixed_accessions = json['matching_accessions'].sort
    assert_equal mixed_accessions, found_mixed_accessions,
                 "Did not return correct array of matching accessions, expected #{found_mixed_accessions} but found #{mixed_accessions}"
    assert_equal "testing", json['studies'].first['term_matches'].first
    assert_equal "API Test Study", json['studies'].last['term_matches'].first

    # test regex escaping
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: 'foobar scp-105 [('))
    assert_response :success

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should return search results using accessions' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # test single accession
    term = Study.where(public: true).first.accession
    execute_http_request(:get, api_v1_search_path(type: 'study', terms: term))
    assert_response :success
    expected_accessions = [term]
    assert_equal expected_accessions, json['matching_accessions'],
                 "Did not return correct array of matching accessions, expected #{expected_accessions} but found #{json['matching_accessions']}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # should generate an auth code for a given user
  test 'should generate auth code' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    execute_http_request(:post, api_v1_create_auth_code_path)
    assert_response :success
    assert_not_nil json['auth_code'], "Did not generate auth code; missing 'totat' field: #{json}"
    auth_code = json['auth_code']
    @user.reload
    assert_equal auth_code, @user.totat

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # should generate a config text file to pass to curl for bulk download
  test 'should generate curl config for bulk download' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    study = Study.find_by(name: "Test Study #{@random_seed}")
    file_types = %w(Expression Metadata).join(',')
    execute_http_request(:post, api_v1_create_auth_code_path)
    assert_response :success
    auth_code = json['auth_code']

    files = study.study_files.by_type(['Expression Matrix', 'Metadata'])
    execute_http_request(:get, api_v1_search_bulk_download_path(
        auth_code: auth_code, accessions: study.accession, file_types: file_types)
    )
    assert_response :success

    config_file = json
    files.each do |file|
      filename = file.upload_file_name
      assert config_file.include?(filename), "Did not find URL for filename: #{filename}"
      output_path = file.bulk_download_pathname
      assert config_file.include?(output_path), "Did not correctly set output path for #{filename} to #{output_path}"
    end

    # ensure bad/missing auth_token return 401
    invalid_auth_code = auth_code.to_i + 1
    execute_http_request(:get, api_v1_search_bulk_download_path(
        auth_code: invalid_auth_code, accessions: study.accession, file_types: file_types)
    )
    assert_response :unauthorized

    execute_http_request(:get, api_v1_search_bulk_download_path(
        auth_code: ' ', accessions: study.accession, file_types: file_types)
    )

    assert_response :unauthorized

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should return preview of bulk download files and total bytes' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    study = Study.find_by(name: "Test Study #{@random_seed}")
    file_types = %w(Expression Metadata)
    execute_http_request(:get, api_v1_search_bulk_download_size_path(
        accessions: study.accession, file_types: file_types.join(','))
    )
    assert_response :success

    expected_response = {
        Metadata: {
            total_files: 1,
            total_bytes: study.metadata_file.upload_file_size
        },
        Expression: {
            total_files: 1,
            total_bytes: study.expression_matrix_files.first.upload_file_size
        }
    }.with_indifferent_access

    assert_equal expected_response, json.with_indifferent_access,
                 "Did not correctly return bulk download sizes, expected #{expected_response} but found #{json}"
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'bulk download should exclude external sequence data' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    study = Study.find_by(name: "API Test Study #{@random_seed}")
    execute_http_request(:post, api_v1_create_auth_code_path)
    assert_response :success
    auth_code = json['auth_code']

    file_types = %w(Cluster Fastq)
    excluded_file = study.study_files.by_type('Fastq').first
    execute_http_request(:get, api_v1_search_bulk_download_path(
        auth_code: auth_code, accessions: study.accession, file_types: file_types)
    )
    assert_response :success

    refute json.include?(excluded_file.name), 'Bulk download config did not exclude external fastq link'

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should filter search results by branding group' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # add study to branding group and search - should get 1 result
    study = Study.find_by(name: "Test Study #{@random_seed}")
    branding_group = BrandingGroup.first
    study.update(branding_group_id: branding_group.id)

    query_parameters = {type: 'study', terms: @random_seed, scpbr: branding_group.name_as_id}
    execute_http_request(:get, api_v1_search_path(query_parameters))
    assert_response :success
    result_count = json['studies'].size
    assert_equal 1, result_count, "Did not find correct number of studies, expected 1 but found #{result_count}"
    found_study = json['studies'].first
    assert found_study['study_url'].include?("scpbr=#{branding_group.name_as_id}"),
           "Did not append branding group identifier to end of study URL: #{found_study['study_url']}"

    # remove study from group and search again - should get 0 results
    study.update(branding_group_id: nil)
    execute_http_request(:get, api_v1_search_path(query_parameters))
    assert_response :success
    assert_empty json['studies'], "Did not find correct number of studies, expected 0 but found #{json['studies'].size}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should run inferred search using facets' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    convention_study = Study.find_by(name: "Test Study #{@random_seed}")
    other_study = Study.find_by(name: "API Test Study #{@random_seed}")
    original_description = other_study.description.to_s.dup
    facet_query = "species:#{HOMO_SAPIENS_FILTER[:id]}"
    execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
    assert_response :success
    expected_accessions = [convention_study.accession]
    assert_equal expected_accessions, json['matching_accessions'],
                 "Did not find expected accessions before inferred search, expected #{expected_accessions} but found #{json['matching_accessions']}"

    # now update non-convention study to include a filter display value in its description
    # this should be picked up by the "inferred" search
    other_study.update(description: HOMO_SAPIENS_FILTER[:name])
    execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
    assert_response :success
    inferred_accessions = [convention_study.accession, other_study.accession]
    assert_equal inferred_accessions, json['matching_accessions'],
                 "Did not find expected accessions after inferred search, expected #{inferred_accessions} but found #{json['matching_accessions']}"
    inferred_study = json['studies'].last # inferred matches should be at the end
    assert inferred_study['inferred_match'],
           "Did not mark last search results as inferred_match: #{inferred_study['inferred_match']} != true"

    # reset description so other tests aren't broken
    other_study.update(description: original_description)

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should run inferred search using facets and phrase' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    convention_study = Study.find_by(name: "Test Study #{@random_seed}")
    other_study = Study.find_by(name: "API Test Study #{@random_seed}")
    original_description = other_study.description.to_s.dup
    species_facet = SearchFacet.find_by(identifier: 'species')
    facet_query = "species:#{HOMO_SAPIENS_FILTER[:id]}"
    other_study.update(description: HOMO_SAPIENS_FILTER[:name])
    search_phrase = "Study #{@random_seed}"
    expected_accessions = [convention_study.accession, other_study.accession]
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
    # reset description so other tests aren't broken
    other_study.update(description: original_description)

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should find intersection of facets on inferred search' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # update other_study to match one filter from facets; should not be inferred since it doesn't meet both criteria
    convention_study = Study.find_by(name: "Test Study #{@random_seed}")
    other_study = Study.find_by(name: "API Test Study #{@random_seed}")
    original_description = other_study.description.to_s.dup
    facet_query = "species:#{HOMO_SAPIENS_FILTER[:id]}+disease:#{NO_DISEASE_FILTER[:id]}"
    other_study.update(description: HOMO_SAPIENS_FILTER[:name])
    execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
    assert_response :success
    expected_accessions = [convention_study.accession]
    assert_equal expected_accessions, json['matching_accessions'],
                 "Did not find expected accessions before inferred search, expected #{expected_accessions} but found #{json['matching_accessions']}"

    # update to match both filters; should be inferred
    double_facet_name = "#{HOMO_SAPIENS_FILTER[:name]} #{NO_DISEASE_FILTER[:name]}"
    other_study.update(description: double_facet_name)
    execute_http_request(:get, api_v1_search_path(type: 'study', facets: facet_query))
    assert_response :success
    inferred_accessions = [convention_study.accession, other_study.accession]
    assert_equal inferred_accessions, json['matching_accessions'],
                 "Did not find expected accessions after inferred search, expected #{inferred_accessions} but found #{json['matching_accessions']}"
    inferred_study = json['studies'].last
    assert inferred_study['inferred_match'], "Did not correctly mark #{other_study.accession} as inferred"
    other_study.update(description: original_description)

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should run preset search' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # run whitelist only search
    @preset_search = PresetSearch.create!(name: 'Preset Search Test', accession_whitelist: %w(SCP1))
    whitelisted_study = Study.first
    execute_http_request(:get, api_v1_search_path(type: 'study', preset_search: @preset_search.identifier))
    assert_response :success
    whitelist_accessions = %w(SCP1)
    assert json['matching_accessions'] == whitelist_accessions,
           "Did not return correct studies for whitelisted preset search; expected #{whitelist_accessions} but found #{json['matching_accessions']}"
    found_preset = json['studies'].first
    assert found_preset['accession'] == whitelisted_study.accession
    assert found_preset['preset_match'], "Did not correctly mark whitelisted study as preset match; #{found_preset['preset_match']}"

    # update to use user-search terms as well, include all studies to widen search
    all_accessions = Study.pluck(:accession)
    @preset_search.update(accession_whitelist: all_accessions)
    @preset_search.reload
    search_terms = "\"API Test Study\""
    execute_http_request(:get, api_v1_search_path(type: 'study', preset_search: @preset_search.identifier, terms: search_terms))
    assert_response :success
    api_test_study = Study.find_by(name: /API Test Study/)
    assert_equal 1, json['studies'].count, "Found wrong number of studies; should be 1 but found #{json['studies'].count}"
    expected_results = [api_test_study.accession]
    assert_equal expected_results, json['matching_accessions'],
                 "Found wrong study with keywords & preset search; expected #{expected_results} but found #{json['matching_accessions']}"
    found_study = json['studies'].first
    assert found_study['preset_match']
    assert_equal ['API Test Study'], found_study['term_matches'], "Did not correctly match on #{search_terms}: #{found_study['term_matches']}"
    @preset_search.destroy # clean up

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should log out user after inactivity' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # make sure user is "active" by updating last_access_at
    @user = User.first
    @user.update_last_access_at!
    # mark study as false to show if a user is signed in or not
    api_test_study = Study.find_by(name: /API Test Study/)
    api_test_study.update(public: false)
    search_terms = "\"API Test Study\""
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
    @user.update_last_access_at!

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end
end
