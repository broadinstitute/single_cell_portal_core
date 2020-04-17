import React from 'react'
import { Router } from '@reach/router'

import SearchPanel from 'components/search/controls/SearchPanel'
import ResultsPanel from 'components/search/results/ResultsPanel'
import StudySearchProvider from 'providers/StudySearchProvider'
import SearchFacetProvider from 'providers/SearchFacetProvider'
import UserProvider from 'providers/UserProvider'
import ErrorBoundary from 'lib/ErrorBoundary'

/**
 * Wrapper component for search and result panels
 */
export default function Covid19PageContent() {
  return (
    <Router>
      <CovidRawPageContent default/>
    </Router>
  )
}

/**
 * The actual rendered content for the covid19 page.
 * Note this needs to be used within a Reach <Router> element or
 * the search component's useLocation hooks will error
 */
function CovidRawPageContent() {
  return (
    <ErrorBoundary>
      <UserProvider>
        <SearchFacetProvider>
          <StudySearchProvider preset="covid19" >
            <ErrorBoundary>
              <SearchPanel showCommonButtons={false}
                showDownloadButton={false}
                keywordPrompt="Search within COVID-19 studies"
                searchOnLoad={true}/>
            </ErrorBoundary>
            <ErrorBoundary>
              <ResultsPanel/>
            </ErrorBoundary>
          </StudySearchProvider>
        </SearchFacetProvider>
      </UserProvider>
    </ErrorBoundary>
  )
}
