
import React, { useContext } from 'react'
import { Router, Link, useLocation } from '@reach/router'

import GeneSearchView from 'components/search/genes/GeneSearchView'
import GeneSearchProvider from 'providers/GeneSearchProvider'
import SearchPanel from 'components/search/controls/SearchPanel'
import ResultsPanel from 'components/search/results/ResultsPanel'
import StudyDetails from 'components/search/results/Study'
import StudySearchProvider, { StudySearchContext } from 'providers/StudySearchProvider'
import SearchFacetProvider from 'providers/SearchFacetProvider'
import UserProvider from 'providers/UserProvider'
import FeatureFlagProvider from 'providers/FeatureFlagProvider'
import ErrorBoundary from 'lib/ErrorBoundary'

/** include search controls and results */
export function StudySearchView() {
  const studySearchState = useContext(StudySearchContext)
  return <>
    <SearchPanel searchOnLoad={true}/>
    <ResultsPanel studySearchState={studySearchState} studyComponent={StudyDetails} />
  </>
}

const LinkableSearchTabs = function(props) {
  // we can't use the regular ReachRouter methods for link highlighting
  // since the Reach router doesn't own the home path
  const location = useLocation()
  const showGenesTab = location.pathname.startsWith('/single_cell/app/genes')
  return (
    <div>
      <nav className="nav search-links">
        <Link to={`/single_cell/app/studies${location.search}`}
          className={showGenesTab ? '' : 'active'}>
          <span className="fas fa-book"></span> Search Studies
        </Link>
        <Link to={`/single_cell/app/genes${location.search}`}
          className={showGenesTab ? 'active' : ''}>
          <span className="fas fa-dna"></span> Search Genes
        </Link>
      </nav>
      <div className="tab-content top-pad">
        <Router basepath="/single_cell">
          <GeneSearchView path="app/genes"/>
          <StudySearchView default/>
        </Router>
      </div>
    </div>
  )
}

/** renders all the page-level providers */
function ProviderStack(props) {
  return (
    <UserProvider>
      <FeatureFlagProvider>
        <SearchFacetProvider>
          <StudySearchProvider>
            <GeneSearchProvider>
              { props.children }
            </GeneSearchProvider>
          </StudySearchProvider>
        </SearchFacetProvider>
      </FeatureFlagProvider>
    </UserProvider>
  )
}

/**
 * Wrapper component for search and result panels
 */
function RawHomePageContent() {
  return (
    <ErrorBoundary>
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
