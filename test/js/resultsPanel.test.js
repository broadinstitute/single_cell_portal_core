import React from 'react'

import StudyResults from
  'components/search/results/StudyResults'
import { StudySearchContext } from
  'providers/StudySearchProvider'
import Study from 'components/search/results//Study'
import ResultsPanel from 'components/search/results/ResultsPanel'
import { mount } from 'enzyme'
React.useLayoutEffect = React.useEffect

describe('<StudyResultsContainer/> rendering>', () => {
  it('should render error panel', () => {
    const resultsPanel = mount(
      <ResultsPanel studySearchState={{ isError: true }}/>
    )
    expect(resultsPanel.find('.error-panel')).toHaveLength(1)
    expect(resultsPanel.find(StudyResults)).toHaveLength(0)
    expect(resultsPanel.find('.loading-panel')).toHaveLength(0)
  })
  it('should render loading-panel', () => {
    const resultsPanel = mount(
      <ResultsPanel studySearchState={{ isError: false, isLoaded: false }}/>
    )
    expect(resultsPanel.find('.loading-panel')).toHaveLength(1)
    expect(resultsPanel.find('.error-panel')).toHaveLength(0)
    expect(resultsPanel.find(StudyResults)).toHaveLength(0)
  })
  it('should render 1 <StudyResults/>', () => {
    const studySearchState = {
      isError: false,
      isLoaded: true,
      results: {
        studies: [
          'SCP1', 'SCP2'
        ],
        facets: {}
      }
    }
    const resultsPanel = mount(
      <ResultsPanel studySearchState={studySearchState} studyComponent={Study} />
    )
    expect(resultsPanel.find(StudyResults)).toHaveLength(1)
    expect(resultsPanel.find('.loading-panel')).toHaveLength(0)
    expect(resultsPanel.find('.error-panel')).toHaveLength(0)
  })
})
