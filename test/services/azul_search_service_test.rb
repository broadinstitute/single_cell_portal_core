# tests for AzulSearchService methods
require 'test_helper'

class AzulSearchServiceTest < ActiveSupport::TestCase

  before(:all) do
    TestDataPopulator.create_sample_search_facets
    SearchFacet.update_all_facet_filters
    @azul_client = ApplicationController.hca_azul_client
    @facets = [
      {
        id: 'species',
        filters: [{ id: 'NCBITaxon9609', name: 'Homo sapiens' }]
      }
    ]
    @terms = %w[pulmonary]
    # expected result from Azul
    @hca_project_shortname = 'HumanTissueTcellActivation'
    @hca_project_id = '4a95101c-9ffc-4f30-a809-f04518a23803'
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Azul Search Test',
                               user: @user,
                               test_array: @@studies_to_clean)
    @mock_facet_query = {
      genusSpecies: {
        is: ['Homo sapiens']
      }
    }.with_indifferent_access
    @mock_term_query = {
      sampleDisease: {
        is: ['chronic obstructive pulmonary disease', 'idiopathic pulmonary fibrosis', 'pulmonary fibrosis']
      }
    }.with_indifferent_access
    @terms_to_facets = [
      {
        id: 'disease',
        filters: [
          { id: 'chronic obstructive pulmonary disease', name: 'chronic obstructive pulmonary disease' },
          { id: 'idiopathic pulmonary fibrosis', name: 'idiopathic pulmonary fibrosis' },
          { id: 'pulmonary fibrosis', name: 'pulmonary fibrosis' }
        ]
      }.with_indifferent_access
    ]
    tcell_json = File.open(Rails.root.join('test/test_data/azul/human_tcell.json')).read
    thymus_json = File.open(Rails.root.join('test/test_data/azul/human_thymus.json')).read
    fibrosis_json = File.open(Rails.root.join('test/test_data/azul/pulmonary_fibrosis.json')).read
    @human_tcell_response = JSON.parse(tcell_json).with_indifferent_access
    @human_thymus_response = JSON.parse(thymus_json).with_indifferent_access
    @fibrosis_response = JSON.parse(fibrosis_json).with_indifferent_access
  end

  after(:all) do
    SearchFacet.destroy_all
  end

  test 'should search Azul using facets' do
    mock = MiniTest::Mock.new
    mock.expect :format_query_from_facets, @mock_facet_query, [@facets]
    mock.expect :merge_query_objects, @mock_facet_query, [@mock_facet_query, nil]
    mock.expect :projects, @human_tcell_response, [{ query: @mock_facet_query }]
    ApplicationController.stub :hca_azul_client, mock do
      results = AzulSearchService.get_results(selected_facets: @facets, terms: nil)
      mock.verify
      assert_includes results.keys, @hca_project_shortname
      project = results[@hca_project_shortname]
      # will always be project manifest file
      manifest = project[:file_information].detect { |f| f[:file_type] == 'Project Manifest' }
      assert manifest.present?
    end
  end

  test 'should search Azul using numeric facets' do
    facets = [
      {
        id: 'organism_age', filters: { min: 1, max: 5, unit: 'years' }
      }.with_indifferent_access
    ]
    mock_age_query = { organismAgeRange: { within: [[31557600, 157788000]] } }
    mock = MiniTest::Mock.new
    mock.expect :format_query_from_facets, mock_age_query, [facets]
    mock.expect :merge_query_objects, mock_age_query, [mock_age_query, nil]
    mock.expect :projects, @human_thymus_response, [{ query: mock_age_query }]
    ApplicationController.stub :hca_azul_client, mock do
      results = AzulSearchService.get_results(selected_facets: facets, terms: nil)
      mock.verify
      assert results.keys.any?
      entry = results.values.sample
      expected_match = {
        organism_age: [{ min: 1, max: 5, unit: 'years' }],
        facet_search_weight: 1
      }.with_indifferent_access
      assert_equal expected_match, entry[:facet_matches]
    end
  end

  test 'should search Azul using terms' do
    mock = MiniTest::Mock.new
    mock.expect :format_query_from_facets, nil, [[]]
    mock.expect :format_facet_query_from_keyword, @terms_to_facets, [@terms]
    mock.expect :format_query_from_facets, @mock_term_query, [@terms_to_facets]
    mock.expect :merge_query_objects, @mock_term_query, [nil, @mock_term_query]
    mock.expect :projects_by_facet, @fibrosis_response, [{ query: @mock_term_query }]
    ApplicationController.stub :hca_azul_client, mock do
      results = AzulSearchService.get_results(selected_facets: [], terms: @terms)
      mock.verify
      project_short_name = 'PulmonaryFibrosisGSE135893'
      assert_includes results.keys, project_short_name
      expected_term_match = %w[pulmonary]
      assert_equal expected_term_match, results.dig(project_short_name, :term_matches)
    end
  end

  test 'should search Azul using facets and terms' do
    facets = [
      {
        id: 'organ',
        filters: [{ id: 'lung', name: 'lung' }]
      }
    ]
    organ_query = { organ: { is: %w[lung] } }
    merged_query = @mock_term_query.merge(organ_query).with_indifferent_access
    mock = MiniTest::Mock.new
    mock.expect :format_query_from_facets, organ_query, [facets]
    mock.expect :format_facet_query_from_keyword, @terms_to_facets, [@terms]
    mock.expect :format_query_from_facets, @mock_term_query, [@terms_to_facets]
    mock.expect :merge_query_objects, merged_query, [organ_query, @mock_term_query]
    mock.expect :projects_by_facet, @fibrosis_response, [{ query: merged_query }]
    ApplicationController.stub :hca_azul_client, mock do
      results = AzulSearchService.get_results(selected_facets: facets, terms: @terms)
      mock.verify
      project_short_name = 'PulmonaryFibrosisGSE135893'
      assert_includes results.keys, project_short_name
      expected_term_match = %w[pulmonary]
      expected_facet_match = {
        organ: [{ id: 'lung', name: 'lung' }],
        disease: [
          { id: 'idiopathic pulmonary fibrosis', name: 'idiopathic pulmonary fibrosis' },
          { id: 'pulmonary fibrosis', name: 'pulmonary fibrosis' }
        ],
        facet_search_weight: 3
      }.with_indifferent_access
      assert_equal expected_term_match, results.dig(project_short_name, :term_matches)
      assert_equal expected_facet_match, results.dig(project_short_name, :facet_matches)
    end
  end

  test 'should get summary file information from project shortnames' do
    projects = %w[HumanTissueTcellActivation KidneySingleCellAtlas Covid19PBMC]
    summary = AzulSearchService.get_file_summary_info(projects)
    assert_equal projects.count, summary.count
    found_projects = summary.map { |project| project[:accession] }
    assert_equal projects, found_projects
    manifests = summary.map { |project| project[:studyFiles].detect { |file| file[:file_type] == 'Project Manifest' } }
    assert_equal 3, manifests.count
    other_files = summary.map { |project| project[:studyFiles].reject { |file| file[:file_type] == 'Project Manifest' } }
                         .flatten
    other_files.each do |file_info|
      assert_equal %w[source count upload_file_size file_format accession project_id file_type is_intermediate].sort, file_info.keys.sort
    end
  end

  test 'should match results on facets' do
    matches = AzulSearchService.get_facet_matches(@human_tcell_response['hits'].first, @facets)
    assert_includes matches.keys, 'species'
    assert_equal 1, matches[:facet_search_weight]
  end

  test 'should append results to studies/facet map' do
    facet_map = {
      @study.accession => {
        species: [{ id: 'NCBITaxon9609', name: 'Homo sapiens' }],
        facet_search_weight: 1
      }
    }.with_indifferent_access
    initial_results = [@study]
    mock = MiniTest::Mock.new
    mock.expect :format_query_from_facets, @mock_facet_query, [@facets]
    mock.expect :format_facet_query_from_keyword, @terms_to_facets, [@terms]
    mock.expect :format_query_from_facets, @mock_term_query, [@terms_to_facets]
    merged_query = @mock_facet_query.merge(@mock_term_query).with_indifferent_access
    mock.expect :merge_query_objects, merged_query, [@mock_facet_query, @mock_term_query]
    mock.expect :projects_by_facet, @fibrosis_response, [{ query: merged_query }]
    fibrosis_shortname = 'PulmonaryFibrosisGSE135893'
    existing_match_data = { 'numResults:scp': 2, 'numResults:total': 2 }.with_indifferent_access # test merging of data
    ApplicationController.stub :hca_azul_client, mock do
      azul_results = AzulSearchService.append_results_to_studies(initial_results,
                                                                 selected_facets: @facets,
                                                                 terms: @terms, facet_map: facet_map,
                                                                 results_matched_by_data: existing_match_data)
      studies = azul_results[:studies]
      facet_map = azul_results[:facet_map]
      match_data = azul_results[:results_matched_by_data]
      assert studies.size > 1
      hca_entry = studies.detect { |study| study.is_a?(Hash) ? study[:accession] == fibrosis_shortname : nil }
      assert hca_entry.present?
      hca_facet_entry = facet_map[fibrosis_shortname]
      assert hca_facet_entry.present?
      assert_equal 3, hca_facet_entry[:facet_search_weight]
      assert_equal 5, hca_entry[:term_search_weight]
      assert_equal @terms, hca_entry[:term_matches]
      assert_equal 1, match_data['numResults:azul']
      assert_equal 3, match_data['numResults:total']
    end
  end

  test 'should retrieve all facets/filters' do
    facets = AzulSearchService.get_all_facet_filters
    expected_keys = %w[organ disease organism_age preservation_method species study_name organ_region
                       library_preparation_protocol sex study_description cell_type biosample_type].sort
    assert_equal expected_keys, facets.keys.sort
    diseases = facets.dig('disease', 'filters')
    assert_includes diseases, 'normal'
    assert_includes diseases, 'multiple sclerosis'
    assert_not facets.dig('disease', 'is_numeric')
    assert facets.dig('organism_age', 'is_numeric')
  end

  test 'should merge facet lists' do
    gallus_filter = { id: 'NCBITaxon_9031', name: 'Gallus gallus' }
    extra_facets = [
      {
        id: 'species',
        filters: [gallus_filter]
      }
    ]
    expected_facets = [
      {
        id: 'species',
        filters: [{ id: 'NCBITaxon9609', name: 'Homo sapiens' }, gallus_filter]
      }
    ]
    assert_equal expected_facets, AzulSearchService.merge_facet_lists(@facets, extra_facets)
    assert_equal expected_facets, AzulSearchService.merge_facet_lists(@facets, nil, extra_facets)
  end

  test 'should compute term match weights' do
    result = {
      name: 'Fake lung study',
      description: 'This is a fake study about human lung cancers.'
    }.with_indifferent_access
    expected_term_match = { total: 2, terms: { lung: 2 } }.with_indifferent_access
    assert_equal expected_term_match, AzulSearchService.get_search_term_weights(result, %w[lung])
  end

  test 'should split large queries into two requests' do
    accession_list = 1.upto(500).map { |n| "FakeHCAProject#{n}" }
    query = { 'project' => { 'is' => accession_list } }
    project_result = @human_tcell_response['hits'].first
    mock_query_result = { 'hits' => Array.new(250, project_result) }
    mock = Minitest::Mock.new
    mock.expect :query_too_large?, true, [query]
    mock.expect :projects, mock_query_result, [Hash]
    mock.expect :projects, mock_query_result, [Hash]
    ApplicationController.stub :hca_azul_client, mock do
      results = AzulSearchService.get_file_summary_info(accession_list)
      mock.verify
      assert results.count == 500
    end
  end
end
