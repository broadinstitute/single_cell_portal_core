require 'test_helper'

class HcaAzulClientTest < ActiveSupport::TestCase

  before(:all) do
    @hca_azul_client = ApplicationController.hca_azul_client
    @project_shortname = 'ImmuneCellExhaustianHIV'
    @project_id = '0fd8f918-62d6-4b8b-ac35-4c53dd601f71'
    @facets = [
      {
        id: 'disease',
        filters: [{ id: 'MONDO_0005109', name: 'HIV infectious disease' }],
        db_facet: SearchFacet.find_or_create_by(identifier: 'disease', data_type: 'string')
      },
      {
        id: 'species',
        filters: [{ id: 'NCBITaxon_9606', name: 'Homo sapiens' }],
        db_facet: SearchFacet.find_or_create_by(identifier: 'species', data_type: 'string')
      }
    ]
    catalogs = @hca_azul_client.catalogs
    @default_catalog = catalogs['default_catalog']
    @query_json = {
      sampleDisease: { is: ['HIV infectious disease'] },
      genusSpecies: { is: ['Homo sapiens'] }
    }.with_indifferent_access

    # check to see if Azul is up and responding as we expect it to
    # running a query for the ImmuneCellExhaustianHIV project should return exactly one match, as well as file
    # if either of these do not return correctly, or error, set a state to skip all tests w/o throwing an error
    @azul_is_ok = false
    begin
      project = @hca_azul_client.projects(query: @query_json, size: 1)
      file = @hca_azul_client.files(query: @query_json, size: 1)
      if get_entries_from_response(project, :projects).present? && file.size == 1
        @azul_is_ok = true
      end
    rescue RestClient::Exception => e
      puts "Error in determining if Azul is healthy: #{e.message}"
    end
    @skip_message = '-- skipping due to Azul API being unavailable or inconsistent --'
  end

  # skip a test if Azul is not up ; prevents unnecessary build failures due to releases/maintenance
  def skip_if_api_down
    unless @azul_is_ok
      puts @skip_message; skip
    end
  end

  # retrieve nested entries from Azul response JSON
  # all responses have a constant structure of hits, pagination, and termFacets
  # under 'hits' there are protocols, entryId, sources, projects, samples, specimens, cellLines, donorOrganisms,
  # organoids, cellSuspensions, and fileTypeSummaries
  def get_entries_from_response(response, key)
    response.with_indifferent_access[:hits].map { |entry| entry[key] }.flatten
  end

  test 'should instantiate client' do
    client = HcaAzulClient.new
    assert_equal HcaAzulClient::BASE_URL, client.api_root
  end

  test 'should check if Azul is up' do
    unless @hca_azul_client.api_available?
      puts @skip_message; skip
    end
    assert @hca_azul_client.api_available?
  end

  test 'should get Azul service status info' do
    unless @hca_azul_client.api_available?
      puts @skip_message; skip
    end
    status = @hca_azul_client.service_information
    assert status['up']
    expected_keys = %w[api_endpoints elasticsearch up]
    assert_equal expected_keys, status.keys.sort
  end

  test 'should get catalogs' do
    skip_if_api_down
    catalogs = @hca_azul_client.catalogs
    default_catalog = catalogs['default_catalog']
    public_catalogs = catalogs['catalogs'].reject { |_, catalog| catalog['internal'] }.keys
    assert default_catalog.present?
    assert_not_empty public_catalogs
    assert_includes public_catalogs, default_catalog
  end

  test 'should get projects' do
    skip_if_api_down
    raw_projects = @hca_azul_client.projects(size: 1)
    projects = get_entries_from_response(raw_projects, :projects)
    assert projects.size == 1
    project = projects.first
    %w[projectId projectTitle projectDescription projectShortname].each do |key|
      assert project[key].present?
    end
  end

  # smoke test for issue with 502 when requesting all human projects
  test 'should get all projects without error' do
    query = { genusSpecies: { is: ['Homo sapiens'] } }.with_indifferent_access
    raw_projects = @hca_azul_client.projects(query: query)
    projects = get_entries_from_response(raw_projects, :projects)
    assert projects.size == HcaAzulClient::MAX_RESULTS
  end

  test 'should query projects using facets' do
    skip_if_api_down
    raw_projects = @hca_azul_client.projects(query: @query_json, size: 1)
    projects = get_entries_from_response(raw_projects, :projects)
    assert_equal 1, projects.size
  end

  test 'should similate OR logic by splitting project queries' do
    # TODO: convert other tests to use mocks to avoid Azul instability/lack of idempotency due to changing data
    hiv_json = File.open(Rails.root.join('test/test_data/azul/disease_hiv.json')).read
    disease_response = JSON.parse(hiv_json).with_indifferent_access
    homo_sapiens_json = File.open(Rails.root.join('test/test_data/azul/species_homo_sapiens.json')).read
    species_response = JSON.parse(homo_sapiens_json).with_indifferent_access
    mock = Minitest::Mock.new
    mock.expect(:code, 200)
    mock.expect(:body, species_response) # body is called twice in ApiHelpers#handle_response
    mock.expect(:body, species_response)
    mock.expect(:code, 200)
    mock.expect(:body, disease_response)
    mock.expect(:body, disease_response)
    RestClient::Request.stub :execute, mock do
      # NOTE: :size here means _per facet_, not total
      projects = @hca_azul_client.projects_by_facet(query: @query_json, size: 1)
      assert_equal 2, projects['hits'].size
      assert_equal %w[0fd8f918-62d6-4b8b-ac35-4c53dd601f71 53c53cd4-8127-4e12-bc7f-8fe1610a715c],
                   projects['project_ids'].sort
      mock.verify
    end
  end

  test 'should get one project' do
    skip_if_api_down
    project = @hca_azul_client.project(@project_id)
    assert_equal @project_id, project['entryId']
    project_detail = project['projects'].first
    assert_equal @project_shortname, project_detail['projectShortname']
  end

  test 'should get files' do
    skip_if_api_down
    files = ApplicationController.hca_azul_client.files(size: 1)
    assert_equal 1, files.size
    file = files.first
    keys = %w[name format size url fileSource].sort
    assert_equal keys, file.keys.sort & keys
  end

  test 'should search files using facets' do
    skip_if_api_down
    files = ApplicationController.hca_azul_client.files(query: @query_json, size: 1)
    assert_equal 1, files.size
    file = files.first
    keys = %w[name format size url fileSource].sort
    assert_equal keys, file.keys.sort & keys
  end

  test 'should get HCA metadata tsv link' do
    skip_if_api_down
    manifest_info = @hca_azul_client.project_manifest_link(@project_id)
    assert manifest_info.present?
    assert_equal 302, manifest_info['Status']
    # make GET on manifest URL and assert contents are HCA metadata
    manifest_response = RestClient.get manifest_info['Location']
    assert_equal 200, manifest_response.code
    raw_manifest = manifest_response.body.split("\r\n")
    headers = raw_manifest.first.split("\t")
    project_id_header = 'project.provenance.document_id'
    assert headers.include? project_id_header
    project_idx = headers.index(project_id_header)
    data_row = raw_manifest.sample.split("\t")
    assert_equal @project_id, data_row[project_idx]
  end

  test 'should format object for query string' do
    query_object = { 'foo' => { 'bar' => 'baz' } }
    expected_response = '%7B%22foo%22%3A%7B%22bar%22%3A%22baz%22%7D%7D'
    formatted_query = @hca_azul_client.format_hash_as_query_string(query_object)
    assert_equal expected_response, formatted_query
    # assert we can get back to original object, but as JSON
    query_as_json = CGI.unescape(formatted_query)
    assert_equal query_object.to_json, query_as_json
  end

  test 'should format query object from search facets' do
    query = @hca_azul_client.format_query_from_facets(@facets)
    expected_query = {
      sampleDisease: { is: ['HIV infectious disease'] },
      genusSpecies: { is: ['Homo sapiens'] }
    }.with_indifferent_access
    assert_equal expected_query, query
  end

  test 'should format numeric facet query' do
    age_facet = [
      {
        id: 'organism_age',
        filters: { min: 1, max: 10, unit: 'years' },
        db_facet: SearchFacet.new(identifier: 'organism_age', data_type: 'number')
      }.with_indifferent_access
    ]
    query = @hca_azul_client.format_query_from_facets(age_facet)
    year_in_seconds = SearchFacet::TIME_MULTIPLIERS['years']
    ten_years = year_in_seconds * 10
    expected_query = {
      organismAgeRange: {
        within: [[year_in_seconds, ten_years]]
      }
    }.with_indifferent_access
    assert_equal expected_query, query
  end

  test 'should convert keyword search into facets' do
    terms = %w[cancer]
    expected_matches = ['cervical cancer', 'colorectal cancer', 'lower gum cancer', 'lung cancer', 'mandibular cancer',
                        'tongue cancer']
    expected_filters = expected_matches.map { |f| { id: f, name: f }.with_indifferent_access }
    expected_facets = [{ id: 'disease', filters: expected_filters, keyword_conversion: true }.with_indifferent_access]
    mock = Minitest::Mock.new
    mock.expect :find_filter_matches, expected_matches, ['cancer', { filter_list: :filters_with_external }]
    mock.expect :identifier, 'disease'
    # handle :with_indifferent_access calls
    mock.expect :is_a?, true, [Class]
    mock.expect :nested_under_indifferent_access, nil
    # pass mock in array to handle .empty? and .each calls
    SearchFacet.stub :find_facets_from_term, [mock] do
      query = @hca_azul_client.format_facet_query_from_keyword(terms)
      mock.verify
      query.each { |facet| facet.delete(:db_facet) }
      assert_equal expected_facets, query
    end
  end

  test 'should ignore common/stop words when creating queries' do
    ignored_terms = HcaAzulClient::IGNORED_WORDS.sample(5)
    facets = @hca_azul_client.format_facet_query_from_keyword(ignored_terms)
    assert_empty facets
  end

  test 'should filter common/stop words from term lists' do
    ignored_terms = HcaAzulClient::IGNORED_WORDS.sample(5)
    assert_empty @hca_azul_client.filter_term_list(ignored_terms)
    assert_empty @hca_azul_client.filter_term_list(ignored_terms.map(&:capitalize)) # case sensitivity
    good_terms = %w[cancer brain human]
    assert_equal good_terms, @hca_azul_client.filter_term_list(good_terms)
  end

  test 'should merge query objects' do
    expected_query = {
      sampleDisease: {
        is: ['HIV infectious disease', 'cervical cancer', 'colorectal cancer', 'lower gum cancer', 'lung cancer',
             'mandibular cancer', 'tongue cancer']
      },
      genusSpecies: {
        is: ["Homo sapiens"]
      }
    }.with_indifferent_access
    facet_query = @hca_azul_client.format_query_from_facets(@facets)
    expected_matches = ['cervical cancer', 'colorectal cancer', 'lower gum cancer', 'lung cancer', 'mandibular cancer',
                        'tongue cancer']
    mock = Minitest::Mock.new
    mock.expect :find_filter_matches, expected_matches, ['cancer', { filter_list: :filters_with_external }]
    mock.expect :identifier, 'disease'
    # handle :with_indifferent_access calls
    mock.expect :is_a?, true, [Class]
    mock.expect :nested_under_indifferent_access, nil
    # pass mock in array to handle .empty? and .each calls
    SearchFacet.stub :find_facets_from_term, [mock] do
      term_facets = @hca_azul_client.format_facet_query_from_keyword(%w[cancer])
      mock.verify
      # merge in search facet to handle :is_numeric? call
      term_facets.first[:db_facet] = SearchFacet.find_or_create_by(identifier: 'disease', data_type: 'string')
      term_query = @hca_azul_client.format_query_from_facets(term_facets)
      merged_query = @hca_azul_client.merge_query_objects(facet_query, term_query)
      assert_equal expected_query, merged_query
      # test nil handling
      merged_with_nil = @hca_azul_client.merge_query_objects(facet_query, nil, term_query)
      assert_equal expected_query, merged_with_nil
    end
  end

  test 'should append HCA catalog name to queries' do
    path = '/index/projects'
    appended_path = @hca_azul_client.append_catalog(path, @default_catalog)
    expected_path = "#{path}?catalog=#{@default_catalog}"
    assert_equal expected_path, appended_path
    path += '?size=1'
    expected_path = "#{path}&catalog=#{@default_catalog}"
    appended_path = @hca_azul_client.append_catalog(path, @default_catalog)
    assert_equal expected_path, appended_path
    # test error handling
    bad_catalog = 'foo'
    assert_raises ArgumentError do
      @hca_azul_client.append_catalog(path, bad_catalog)
    end
  end

  test 'should determine if query is too large' do
    accession_list = 1.upto(500).map { |n| "FakeHCAProject#{n}" }
    query = { project: { is: accession_list } }
    assert @hca_azul_client.query_too_large?(query)
    assert_not @hca_azul_client.query_too_large?({ project: { is: accession_list.take(10) } })
  end

  test 'should not retry any error status code' do
    ApiHelpers::RETRY_STATUS_CODES.each do |code|
      assert_not @hca_azul_client.should_retry?(code)
    end
  end
end
