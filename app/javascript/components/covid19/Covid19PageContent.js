import React, { useContext } from 'react'
import { Router } from '@reach/router'

import SearchPanel from 'components/search/controls/SearchPanel'
import ResultsPanel from 'components/search/results/ResultsPanel'
import StudySearchProvider, { StudySearchContext } from 'providers/StudySearchProvider'
import SearchFacetProvider from 'providers/SearchFacetProvider'
import UserProvider from 'providers/UserProvider'
import ErrorBoundary from 'lib/ErrorBoundary'
import StudyDetails from 'components/search/results/Study'


/**
 * Wrapper component for search and result panels
 */
export default function Covid19PageContent() {
  return (
    <Router>
      <CovidPageContainer default/>
    </Router>
  )
}

/**
 * The actual rendered content for the covid19 page.
 * Note this needs to be used within a Reach <Router> element or
 * the search component's useLocation hooks will error
 */
function CovidPageContainer() {
  return (
    <ErrorBoundary>
      <UserProvider>
        <SearchFacetProvider>
          <StudySearchProvider preset="covid19" >
            <CovidPageSearchContent/>
          </StudySearchProvider>
        </SearchFacetProvider>
      </UserProvider>
    </ErrorBoundary>
  )
}

function CovidPageSearchContent() {
  const studySearchState = useContext(StudySearchContext)
  return (<>
    <ErrorBoundary>
      <SearchPanel showCommonButtons={false}
        keywordPrompt="Search within COVID-19 studies"
        searchOnLoad={true}/>
    </ErrorBoundary>
    <ErrorBoundary>
      <ResultsPanel studySearchState={studySearchState} studyComponent={StudyDetails}/>
    </ErrorBoundary>
  </>)
}
