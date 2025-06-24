import React from 'react'

import StudySearchResult from 'components/search/results/StudySearchResult'
import ResultsPanel from 'components/search/results/ResultsPanel'
import { render } from '@testing-library/react'
React.useLayoutEffect = React.useEffect

describe('<StudyResultsContainer/> rendering>', () => {
  it('should render error panel', () => {
    const { container } = render(
      <ResultsPanel studySearchState={{ isError: true }}/>
    )
    expect(container.getElementsByClassName('error-panel')).toHaveLength(1)
    expect(container.getElementsByClassName('loading-panel')).toHaveLength(0)
    expect(container.getElementsByClassName('results-header')).toHaveLength(0)
  })
  it('should render loading-panel', () => {
    const { container } = render(
      <ResultsPanel studySearchState={{ isError: false, isLoaded: false }}/>
    )
    expect(container.getElementsByClassName('loading-panel')).toHaveLength(1)
    expect(container.getElementsByClassName('error-panel')).toHaveLength(0)
    expect(container.getElementsByClassName('results-header')).toHaveLength(0)
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
    const { container } = render(
      <ResultsPanel studySearchState={studySearchState} studyComponent={StudySearchResult} />
    )
    expect(container.getElementsByClassName('loading-panel')).toHaveLength(0)
    expect(container.getElementsByClassName('error-panel')).toHaveLength(0)
    expect(container.getElementsByClassName('results-header')).toHaveLength(1)
  })
  it('should render message about HCA when no results found', () => {
    const studySearchState = {
      isError: false,
      isLoaded: true,
      params: { external: '' },
      results: {
        studies: [],
        facets: {}
      }
    }
    const { container } = render(
      <ResultsPanel studySearchState={studySearchState}/>
    )
    expect(container.getElementsByClassName('loading-panel')).toHaveLength(0)
    expect(container.getElementsByClassName('error-panel')).toHaveLength(0)
    expect(container.getElementsByClassName('results-header')).toHaveLength(0)
    expect(container.textContent).toContain('Search HCA Data Portal?')
  })
  it('should not render message about HCA if already requested', () => {
    const studySearchState = {
      isError: false,
      isLoaded: true,
      params: { external: 'hca' },
      results: {
        studies: [],
        facets: { cell_type: 'CL_0000548' }
      }
    }
    const { container } = render(
      <ResultsPanel studySearchState={studySearchState} />
    )
    expect(container.textContent).not.toContain('Search HCA Data Portal?')
  })
})
