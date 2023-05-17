require 'test_helper'
require 'api_test_helper'
require 'integration_test_helper'
require 'includes_helper'

class RequestUtilsTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:user, registered_for_firecloud: true, test_array: @@users_to_clean)

    @public_study = FactoryBot.create(:detached_study,
                                      name_prefix: 'Public study',
                                      public: true,
                                      user: @user,
                                      test_array: @@studies_to_clean)

    @private_study = FactoryBot.create(:detached_study,
                                       name_prefix: 'Private study',
                                       public: false,
                                       user: @user,
                                       test_array: @@studies_to_clean)
  end

  test 'should sanitize page inputs' do
    assert_equal(2, RequestUtils.sanitize_page_param(2))
    assert_equal(5, RequestUtils.sanitize_page_param('5'))
    assert_equal(1, RequestUtils.sanitize_page_param(nil))
    assert_equal(1, RequestUtils.sanitize_page_param('foobar'))
    assert_equal(1, RequestUtils.sanitize_page_param('undefined'))
    assert_equal(1, RequestUtils.sanitize_page_param('0'))
    assert_equal(1, RequestUtils.sanitize_page_param('-6'))
  end

  test 'should exclude NaN from minmax for numeric arrays' do
    source = [Float::NAN, 1.0, 100.0]
    numeric_array = 1000.times.map {source.sample}
    min, max = RequestUtils.get_minmax(numeric_array)
    assert_equal 1.0, min, "Did not get expected min of 1.0: #{min}"
    assert_equal 100.0, max, "Did not get expected max of 100.0: #{max}"
  end

  test 'should sanitize search terms' do
    # test non-ASCII characters
    search_terms = 'This is an ASCII-compatible string'
    sanitized_terms = RequestUtils.sanitize_search_terms search_terms
    assert_equal search_terms, sanitized_terms,
                 "Valid search string was changed by sanitizer; #{search_terms} != #{sanitized_terms}"
    invalid_terms = 'This has încømpåtiblé characters'
    expected_sanitized = 'This has ?nc?mp?tibl? characters'
    sanitized_invalid = RequestUtils.sanitize_search_terms invalid_terms
    assert_equal expected_sanitized, sanitized_invalid,
                 "Sanitizer did not strip illegal characters from search terms; #{expected_sanitized} != #{sanitized_invalid}"

    # test html tags
    html_string = "This string has <a href='javascript:alert(\"bad stuff!\")'>html content</a>"
    expected_output = 'This string has html content'
    sanitized_html = RequestUtils.sanitize_search_terms html_string
    assert_equal sanitized_html, expected_output, "Did not correctly remove html tags: #{expected_output} != #{sanitized_html}"

    # test array inputs
    input_list = %w(Gad1 Gad2 Egfr)
    expected_output = input_list.join(',')
    sanitized_genes = RequestUtils.sanitize_search_terms input_list
    assert_equal sanitized_genes, expected_output,
                 "Did not correctly return array of genes as comma-delimited list; #{sanitized_genes} != #{expected_output}"

    invalid_list = %w(Gåd1 Gåd2 Égfr)
    invalid_output = 'G?d1,G?d2,?gfr'
    sanitized_invalid_list = RequestUtils.sanitize_search_terms invalid_list
    assert_equal invalid_output, sanitized_invalid_list,
                 "Did not correctly sanitize characters from list; #{invalid_output} != #{sanitized_invalid_list}"
  end

  test 'should format text for matching' do
    search_string = '   ThiS iS a long %%  STRING with non\  word ... charaCTers    iN   It !!!!   '
    expected_string = 'this is a long string with non word characters in it'
    assert_equal expected_string, RequestUtils.format_text_for_match(search_string)
  end

  test 'should format file path for os' do
    path = 'path/to/some/file.txt'
    unix_os_list = ['Mac OS X', 'macOSX', 'Generic Linux', 'Android', 'iOS (iPhone)']
    unix_os_list.each do |operating_system|
      formatted_path = RequestUtils.format_path_for_os(path, operating_system)
      assert_equal path, formatted_path
    end
    windows_path = RequestUtils.format_path_for_os(path, 'Windows')
    expected_path = "path\\to\\some\\file.txt"
    assert_equal expected_path, windows_path
  end

  test 'should format exceptions as JSON' do
    exception = ArgumentError.new('this is the error')
    request = ActionDispatch::TestRequest.create('action_dispatch.exception' => exception)
    json_response = RequestUtils.exception_json(request)
    assert_equal %i[error error_class source], json_response.keys
    assert_equal exception.message, json_response[:error]
    assert_equal exception.class.name, json_response[:error_class]
  end

  test 'should ignore static asset errors' do
    error = RuntimeError.new('this is a normal error')
    assert_not RequestUtils.static_asset_error?(error)
    paths = [
      'No route matches [GET] "/apple-touch-icon-precomposed.png"',
      'No route matches [GET] "/static/img/logo.1a41f6387d69.svg"',
      'No route matches [GET] "/single_cell/packs/foo.js"',
      'No route matches [GET] "/single_cell/assets/does-not-exist.css"'
    ]
    paths.each do |path|
      asset_error = ActionController::RoutingError.new(path)
      assert RequestUtils.static_asset_error?(asset_error)
    end
  end

  test 'should set reproducible cache path on viz API requests' do
    path = '/single_cell/api/v1/clusters/SCP1234/UMAP'
    parameters = {
      annotation_name: 'cell_type__ontology_label',
      annotation_scope: 'study',
      annotation_type: 'group',
      cluster_name: 'UMAP',
      fields: 'coordinates,cells,annotation',
      subsample: 'all',
      study_id: 'SCP1234'
    }
    expected_digest = '50122a95a87f2ffa6be253a216f662388988c2e61e530e8d9423b8c97b7c1d60'
    expected_path = "_single_cell_api_v1_clusters_SCP1234_UMAP_#{expected_digest}"
    assert_equal expected_path, RequestUtils.get_cache_path(path, parameters)
    # reorder parameters to ensure idempotency
    new_params = {
      annotation_type: 'group',
      subsample: 'all',
      annotation_scope: 'study',
      cluster_name: 'UMAP',
      fields: 'coordinates,cells,annotation',
      study_id: 'SCP1234',
      annotation_name: 'cell_type__ontology_label'
    }
    assert_equal expected_path, RequestUtils.get_cache_path(path, new_params)
  end

  test 'should call to get read-only SA token for signed out user on public study' do
    # Validates the most common scenario for client-side bucket access, e.g. a typical
    # user exploring an SCP study they learned about in a scientific journal

    mock = MiniTest::Mock.new
    mock.expect :call, nil, []

    sign_out @user

    ApplicationController.read_only_firecloud_client.stub :valid_access_token, mock do
      RequestUtils.get_read_access_token(@public_study, @user)
      mock.verify
    end
  end

  test 'should call to get read-only SA token for signed in user on public study' do
    # Validates a scenario for client-side bucket access, e.g. a particularly engaged
    # user exploring others' studies

    mock = MiniTest::Mock.new
    mock.expect :call, nil, []

    sign_in @user

    ApplicationController.read_only_firecloud_client.stub :valid_access_token, mock do
      RequestUtils.get_read_access_token(@public_study, @user)
      mock.verify
    end
  end

  test 'should call to get user storage token for signed in user on private study' do
    # Validates a scenario for client-side bucket access, e.g. an owner checking things
    # before publishing their SCP study

    mock = MiniTest::Mock.new
    mock.expect :call, nil, [@private_study]

    @user.stub :token_for_storage_object, mock do
      RequestUtils.get_read_access_token(@private_study, @user)
      mock.verify
    end
  end

end
