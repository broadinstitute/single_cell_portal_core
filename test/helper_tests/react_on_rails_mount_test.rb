require 'test_helper'

class ReactOnRailsMountTest < ActionView::TestCase
  include ReactOnRailsHelper

  test 'study usage mount emits react on rails component metadata' do
    markup = react_component(
      'StudyUsageInfo',
      props: {
        study: {
          accession: 'SCP12',
          name: 'Usage test study'
        }
      },
      id: 'study-usage-react-root'
    )

    assert_includes markup, 'id="study-usage-react-root"'
    assert_includes markup, 'class="js-react-on-rails-component"'
    assert_includes markup, 'data-component-name="StudyUsageInfo"'
    assert_includes markup, 'data-dom-id="study-usage-react-root"'
  end
end
