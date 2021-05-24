
import React, { useContext, useState } from 'react'
import { Router, Link, useLocation } from '@reach/router'

import GeneSearchView from 'components/search/genes/GeneSearchView'
import GeneSearchProvider from 'providers/GeneSearchProvider'
import SearchPanel from 'components/search/controls/SearchPanel'
import ResultsPanel from 'components/search/results/ResultsPanel'
import StudyDetails from 'components/search/results/Study'
import StudySearchProvider, { StudySearchContext } from 'providers/StudySearchProvider'
import SearchFacetProvider from 'providers/SearchFacetProvider'
import UserProvider from 'providers/UserProvider'
import ErrorBoundary from 'lib/ErrorBoundary'
import * as queryString from 'query-string'

import useHomePageRouter from './search_xds/HomePageRouter'

/** include search controls and results */
export function StudySearchView({ advancedSearchDefault }) {
  const studySearchState = useContext(StudySearchContext)
  return <>
    <SearchPanel advancedSearchDefault={advancedSearchDefault} searchOnLoad={true}/>
    <ResultsPanel studySearchState={studySearchState} studyComponent={StudyDetails} />
  </>
}

const RoutableSearchTabs = function() {
  // stores the basic study overview data from the server, used to determine what views are available
  const [homeInfo, setHomeInfo] = useState(null)
  const { homeParams, updateHomeParams, clearHomeParams, routerLocation } = useHomePageRouter()

  const location = useLocation()
  const basePath = location.pathname.includes('covid19') ? '/single_cell/covid19' : '/single_cell'
  const showGenesTab = location.pathname.includes('/app/genes')
  const queryParams = queryString.parse(location.search)
  // the queryParams object does not support the more typical hasOwnProperty test
  const advancedSearchDefault = ('advancedSearch' in queryParams)

  return (
    <div>
      <nav className="nav search-links" data-analytics-name="search" role="tablist">
        <Link to={`${basePath}/app/studies${location.search}`}
          className={showGenesTab ? '' : 'active'}>
          <span className="fas fa-book"></span> Search Studies
        </Link>
        <Link to={`${basePath}/app/genes${location.search}`}
          className={showGenesTab ? 'active' : ''}>
          <span className="fas fa-dna"></span> Search Genes
        </Link>
      </nav>
      <div className="tab-content top-pad">
        <Router basepath={basePath}>
          <GeneSearchView path="app/genes"/>
          <StudySearchView
            advancedSearchDefault={advancedSearchDefault}
            homeParams={homeParams}
            updateHomeParams={updateHomeParams}
            clearHomeParams={clearHomeParams}
            routerLocation={routerLocation}
            homeInfo={homeInfo}
            setHomeInfo={setHomeInfo}
            default
          />
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
      <ProviderStack>
        <RoutableSearchTabs/>
      </ProviderStack>
    </ErrorBoundary>
  )
}

/** Include Reach router */
export default function HomePageContentXds() {
  return (<Router>
    <RawHomePageContent default/>
  </Router>)
}
