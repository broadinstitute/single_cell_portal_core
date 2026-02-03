require 'api_test_helper'
require 'test_helper'
require 'includes_helper'

class PresetSearchesControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               user: @user,
                               name_prefix: 'Preset Search Test Study',
                               test_array: @@studies_to_clean)
    @search = PresetSearch.create!(name: 'Test Search', search_terms: ['Preset Search'],
                                   facet_filters: %w[species:NCBITaxon_9606 disease:MONDO_0000001],
                                   accession_list: [@study.accession])
  end

  after(:all) do
    PresetSearch.destroy_all
  end

  setup do
    OmniAuth.config.test_mode = true
    sign_in_and_update @user
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test 'gets index' do
    get preset_searches_path
    assert_response :success
    assert_select 'table#searches', 1, 'Did not preset search table'
  end

  test 'gets new' do
    get new_preset_search_path
    assert_response :success
    assert_select 'form#preset-search-form', 1, 'Did not find preset search form'
  end

  test 'creates updates and deletes preset search' do
    study_accession = Study.all.sample.accession
    terms = "test data \"this is a phrase\""
    facets = 'disease:MONDO_0000001+species:NCBITaxon_9606'
    preset_search_params = {
      preset_search: {
        name: 'My Preset Search',
        accession_list: study_accession,
        search_terms: terms,
        facet_filters: facets
      }
    }
    post preset_searches_path, params: preset_search_params
    follow_redirect!
    assert_response :success
    @preset_search = PresetSearch.find_by(name: 'My Preset Search')
    assert @preset_search.present?, 'Preset search did not get created'
    assert_equal @preset_search.accession_list, [study_accession],
                 "Did not properly set accession list: #{study_accession} is not in #{@preset_search.accession_list}"
    assert_equal @preset_search.keyword_query_string, terms,
                 "Search terms not correctly set: #{@preset_search.keyword_query_string} != #{terms}"
    assert_equal @preset_search.facet_query_string, facets,
                 "Facets not correctly set: #{@preset_search.facet_query_string} != #{facets}"

    new_terms = 'update'
    update_params = {
      preset_search: {
        search_terms: new_terms,
        facet_filters: facets,
        accession_list: study_accession
      }
    }
    patch preset_search_path(@preset_search), params: update_params
    follow_redirect!
    assert_response :success
    @preset_search.reload
    assert @preset_search.present?, 'Preset search did not get loaded'
    assert_equal @preset_search.keyword_query_string, new_terms,
                 "Search terms did not update: #{new_terms} is not in #{@preset_search.keyword_query_string}"
    assert_equal @preset_search.accession_list, [study_accession],
                 "Accession list changed when it shouldn't have; #{study_accession} is not in #{@preset_search.accession_list}"
    assert_equal @preset_search.facet_query_string, facets,
                 "Facets were changed when they shouldn't have; #{facets} != #{@preset_search.facet_query_string}"


    delete preset_search_path(@preset_search)
    follow_redirect!
    assert_response :success
    assert_equal 1, PresetSearch.count,
                 "Did not delete search, expected count of 1 but found #{PresetSearch.count}"
  end

  test 'shows preset search' do
    get preset_search_path(@search)
    assert_response :success
    assert_select 'dl#preset-search-attributes', 1, 'Did not find preset search attributes'
  end

  test 'gets edit for preset search' do
    get edit_preset_search_path(@search)
    assert_response :success
    assert_select 'form#preset-search-form', 1, 'Did not find preset search form'
  end
end
