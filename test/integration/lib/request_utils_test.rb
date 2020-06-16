require "test_helper"

class RequestUtilsTest < ActiveSupport::TestCase

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
    assert_equal 100.0, min, "Did not get expected max of 100.0: #{max}"
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
end
