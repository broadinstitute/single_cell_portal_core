require 'test_helper'

class StudySearchResultsObjectsTest < ActiveSupport::TestCase

  test 'should merge facet match data' do
    study_data = {
      cell_type: [{ id: 'CL_0000236', name: 'B cell' }],
      organ: [{ id: 'UBERON_0000970', name: 'eye' }],
      facet_search_weight: 2
    }
    keyword_data = {
      cell_type: [
        { id: 'bipolar neuron', name: 'bipolar neuron' },
        { id: 'retinal bipolar neuron', name: 'retinal bipolar neuron' },
        { id: 'retinal cone cell', name: 'retinal cone cell' },
        { id: 'B cell', name: 'B cell' },
        { id: 'amacrine cell', name: 'amacrine cell' }
      ],
      facet_search_weight: 5
    }
    merged_data = Api::V1::StudySearchResultsObjects.merge_facet_matches(study_data, keyword_data)
    assert_equal 6, merged_data[:facet_search_weight]
    expected_names = ['B cell', 'bipolar neuron', 'retinal bipolar neuron', 'retinal cone cell', 'amacrine cell']
    assert_equal expected_names, merged_data[:cell_type].map { |filter| filter[:name]}
  end

  test 'should remove any newlines from result descriptions' do
    description = "This is a study description.\nIt has newlines.\n\nAnd some more.\r\n\r\nAnd some Windows newlines."
    cleaned_description = Api::V1::StudySearchResultsObjects.strip_newlines(description)
    assert_equal 'This is a study description. It has newlines.  And some more.  And some Windows newlines.',
                 cleaned_description
  end
end
