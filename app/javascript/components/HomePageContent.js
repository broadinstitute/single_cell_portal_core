
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
export function StudySearchView({presetEnv}) {
  const studySearchState = useContext(StudySearchContext)
  return <>
    <SearchPanel searchOnLoad={true}
                 showCommonButtons={presetEnv.showCommonButtons}
                 keywordPrompt={presetEnv.keywordPrompt}/>
    <ResultsPanel studySearchState={studySearchState} studyComponent={StudyDetails} />
  </>
}

/** Displays a gene and study search tabs that are URL linkable */
const LinkableSearchTabs = function({presetEnv}) {
  // we can't use the regular ReachRouter methods for link highlighting
  // since the Reach router doesn't own the home path
  const location = useLocation()
  const showGenesTab = location.pathname.indexOf('app/genes') >= 0
  let basePath = 'single_cell'
  if (location.pathname.indexOf('single_cell/covid19') >= 0) {
    basePath = 'single_cell/covid19'
  }
  return (
    <div>
      <nav className="nav search-links">
        <Link to={`/${basePath}/app/studies${location.search}`}
          className={showGenesTab ? '' : 'active'}>
          <span className="fas fa-book"></span> Search Studies
        </Link>
        <Link to={`/${basePath}/app/genes${location.search}`}
          className={showGenesTab ? 'active' : ''}>
          <span className="fas fa-dna"></span> Search Genes
        </Link>
      </nav>
      <div className="tab-content top-pad">
        <Router basepath={`/${basePath}`}>
          <GeneSearchView path="app/genes" keywordPrompt={presetEnv.geneKeywordPrompt}/>
          <StudySearchView default presetEnv={presetEnv}/>
        </Router>
      </div>
    </div>
  )
}

/** renders all the page-level providers */
function ProviderStack({presetEnv, children}) {
  return (
    <UserProvider>
      <FeatureFlagProvider>
        <SearchFacetProvider>
          <StudySearchProvider preset={presetEnv.preset}>
            <GeneSearchProvider preset={presetEnv.preset}>
              { children }
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
function RawHomePageContent({presetEnv}) {
  return (
    <ErrorBoundary>
      <ProviderStack presetEnv={presetEnv}>
        <LinkableSearchTabs presetEnv={presetEnv}/>
      </ProviderStack>
    </ErrorBoundary>
  )
}

/**
 * Wrapper component to include Reach router
 * presetEnv contains display-style arguments suitable for a custom space (e.g. covid19)
 * or perhaps eventually more customized branding group text
 */
export default function HomePageContent({presetEnv}) {
  if (!presetEnv) {
    presetEnv = {
      showCommonButtons: undefined,
      keywordPrompt: undefined,
      geneKeywordPrompt: undefined,
      preset: undefined
    }
  }
  return (<Router>
    <RawHomePageContent presetEnv={presetEnv} default/>
  </Router>)
}
