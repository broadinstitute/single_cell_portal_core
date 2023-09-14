
import React, { useContext } from 'react'
import { Router, Link, useLocation } from '@reach/router'

import GeneSearchView from '~/components/search/genes/GeneSearchView'
import MessageModal from '~/lib/MessageModal'
import GeneSearchProvider from '~/providers/GeneSearchProvider'
import SearchPanel from '~/components/search/controls/SearchPanel'
import ResultsPanel from '~/components/search/results/ResultsPanel'
import StudyDetails from '~/components/search/results/StudySearchResult'
import StudySearchProvider, { StudySearchContext } from '~/providers/StudySearchProvider'
import SearchFacetProvider from '~/providers/SearchFacetProvider'
import UserProvider, { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'
import ErrorBoundary from '~/lib/ErrorBoundary'

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
  const basePath = location.pathname.includes('covid19') ? '/single_cell/covid19' : '/single_cell'
  const showGenesTab = location.pathname.includes('/app/genes')
  const featureFlags = getFeatureFlagsWithDefaults()
  const showVizAppcue = featureFlags && featureFlags?.show_appcue_viz_tour

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
        { showVizAppcue &&
          <a className='btn btn-primary appcue-pin'
             href='https://singlecell.broadinstitute.org/single_cell/study/SCP2271'
             data-analytics-name='appcue-viz-demo'>
            Demo of SCP visualization tools
          </a>
        }
      </nav>
      <div className="tab-content top-pad">
        <Router basepath={basePath}>
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
