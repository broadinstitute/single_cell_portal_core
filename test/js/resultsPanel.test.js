import React from 'react'

import StudyResults from
  'components/search/results/StudyResults'
import { StudySearchContext } from
  'providers/StudySearchProvider'
import ResultsPanel from 'components/search/results/ResultsPanel'
import { mount } from 'enzyme'
React.useLayoutEffect = React.useEffect
describe('<StudyResultsContainer/> rendering>', () => {
  it('should render error panel', () => {
    const resultsPanel = mount(
      <StudySearchContext.Provider value={{ isError: true }}>
        <ResultsPanel/>
      </StudySearchContext.Provider>)
    expect(resultsPanel.find('.error-panel')).toHaveLength(1)
    expect(resultsPanel.find(StudyResults)).toHaveLength(0)
    expect(resultsPanel.find('.loading-panel')).toHaveLength(0)
  })
  it('should render loading-panel', () => {
    const resultsPanel = mount(
      <StudySearchContext.Provider value={
        {
          isError: false,
          isLoaded: false
        }}>
        <ResultsPanel/>
      </StudySearchContext.Provider>)
    expect(resultsPanel.find('.loading-panel')).toHaveLength(1)
    expect(resultsPanel.find('.error-panel')).toHaveLength(0)
    expect(resultsPanel.find(StudyResults)).toHaveLength(0)
  })
  it('should render 1 <StudyResults/>', () => {
    const resultsPanel = mount(
      <StudySearchContext.Provider value={
        {
          isError: false,
          isLoaded: true,
          results: {
            studies: [
              'SCP1', 'SCP2'
            ],
            facets: {}
          }
        }}>
        <ResultsPanel/>
      </StudySearchContext.Provider>)
    expect(resultsPanel.find(StudyResults)).toHaveLength(1)
    expect(resultsPanel.find('.loading-panel')).toHaveLength(0)
    expect(resultsPanel.find('.error-panel')).toHaveLength(0)
  })
})
