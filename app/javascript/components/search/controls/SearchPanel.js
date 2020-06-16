import React, { useContext, useEffect } from 'react'

import KeywordSearch from './KeywordSearch'
import FacetsPanel from './FacetsPanel'
import DownloadButton from './DownloadButton'
import DownloadProvider from 'providers/DownloadProvider'
import { StudySearchContext } from 'providers/StudySearchProvider'
import { FeatureFlagContext } from 'providers/FeatureFlagProvider'

function CommonSearchButtons() {
  const searchState = useContext(StudySearchContext)
  function handleClick(ordering) {
    searchState.updateSearch({ order: ordering })
  }
  return (
    <>
      <span className="facet">
        <a onClick={ () => handleClick('popular') }>Most Popular</a>
      </span>
      <span className="facet">
        <a onClick={ () => handleClick('recent') }>Most Recent</a>
      </span>
    </>
  )
}

/**
 * Component for SCP faceted search UI
 * showCommonButtons defaults to true
 */
export default function SearchPanel({
  showCommonButtons,
  keywordPrompt,
  searchOnLoad
}) {
  // Note: This might become  a Higher-Order Component (HOC).
  // This search component is currently specific to the "Studies" tab, but
  // could possibly also enable search for "Genes" and "Cells" tabs.
  const featureFlagState = useContext(FeatureFlagContext)
  const searchState = useContext(StudySearchContext)
  let searchButtons = <></>
  let downloadButtons = <></>
  if (showCommonButtons !== false) {
    searchButtons = <CommonSearchButtons/>
  }
  if (featureFlagState.faceted_search) {
    searchButtons = <FacetsPanel/>
    downloadButtons = <DownloadProvider><DownloadButton /></DownloadProvider>
  }

  useEffect(() => {
    // if a search isn't already happening, and searchOnLoad is specified, perform one
    if (!searchState.isLoading && !searchState.isLoaded && searchOnLoad) {
      searchState.performSearch()
    }
  })

  return (
    <div id='search-panel'>
      <KeywordSearch keywordPrompt={keywordPrompt}/>
      { searchButtons }
      { downloadButtons }
    </div>
  )
}

