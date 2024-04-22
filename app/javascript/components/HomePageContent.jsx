
import React, { useContext, useState, useEffect } from 'react'
import { Router, Link, useLocation } from '@reach/router'

import GeneSearchView from '~/components/search/genes/GeneSearchView'
import MessageModal from '~/lib/MessageModal'
import GeneSearchProvider from '~/providers/GeneSearchProvider'
import SearchPanel from '~/components/search/controls/SearchPanel'
import ResultsPanel from '~/components/search/results/ResultsPanel'
import StudyDetails from '~/components/search/results/StudySearchResult'
import StudySearchProvider, { StudySearchContext } from '~/providers/StudySearchProvider'
import SearchFacetProvider from '~/providers/SearchFacetProvider'
import UserProvider, { isUserLoggedIn } from '~/providers/UserProvider'
import { fetchBookmarks } from '~/lib/scp-api'
import { logError } from '~/lib/metrics-api'
import ErrorBoundary from '~/lib/ErrorBoundary'

/** include search controls and results */
export function StudySearchView({bookmarks}) {
  const studySearchState = useContext(StudySearchContext)
  return <>
    <SearchPanel searchOnLoad={true}/>
    <ResultsPanel studySearchState={studySearchState} studyComponent={StudyDetails} bookmarks={bookmarks} />
  </>
}

const LinkableSearchTabs = function(props) {
  // we can't use the regular ReachRouter methods for link highlighting
  // since the Reach router doesn't own the home path
  const location = useLocation()
  const basePath = location.pathname.includes('covid19') ? '/single_cell/covid19' : '/single_cell'
  const showGenesTab = location.pathname.includes('/app/genes')
  const [bookmarks, setBookmarks] = useState([])
  const [hasLoadedBookmarks, setHasLoadedBookmarks] = useState(null)

  async function loadUserBookmarks() {
    setHasLoadedBookmarks(true) // short-circuit multiple calls to load bookmarks
    try {
      const userBookmarks = await fetchBookmarks()
      setBookmarks(userBookmarks)
    } catch (error) {
      const errorMsg = error.message
      logError(errorMsg, error)
    }
  }

  useEffect(() => {
    if (isUserLoggedIn() && !hasLoadedBookmarks) {
      loadUserBookmarks()
    }
  }, [])

  // the queryParams object does not support the more typical hasOwnProperty test
  return (
    <div>
        <nav className="nav search-links" data-analytics-name="search" role="tablist">
          <Link to={`${basePath}/app/studies${location.search}`}
                className={showGenesTab ? '' : 'active'}>
            <span className="fas fa-book"></span> Search studies
          </Link>
          <Link to={`${basePath}/app/genes${location.search}`}
                className={showGenesTab ? 'active' : ''}>
            <span className="fas fa-dna"></span> Search genes
          </Link>
        </nav>
      <div className="tab-content top-pad">
        <Router basepath={basePath}>
          <GeneSearchView path="app/genes" bookmarks={bookmarks}/>
          <StudySearchView default bookmarks={bookmarks}/>
        </Router>
      </div>
    </div>
  )
}

/** renders all the page-level providers */
function ProviderStack(props) {
  return (
    <UserProvider>
      <SearchFacetProvider>
        <StudySearchProvider>
          <GeneSearchProvider>
            { props.children }
          </GeneSearchProvider>
        </StudySearchProvider>
      </SearchFacetProvider>
    </UserProvider>
  )
}

/**
 * Wrapper component for search and result panels
 */
function RawHomePageContent() {
  return (
    <ErrorBoundary>
      <MessageModal/>
      <ProviderStack>
        <LinkableSearchTabs/>
      </ProviderStack>
    </ErrorBoundary>
  )
}

/** Include Reach router */
export default function HomePageContent() {
  return (<Router>
    <RawHomePageContent default/>
  </Router>)
}
