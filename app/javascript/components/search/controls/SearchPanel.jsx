import React, { useContext, useEffect } from 'react'

import KeywordSearch from './KeywordSearch'
import FacetsPanel from './FacetsPanel'
import DownloadButton from './download/DownloadButton'
import { StudySearchContext } from '~/providers/StudySearchProvider'

/** helper method as, for unknown reasons, clicking the bootstrap modal auto-scrolls the page down */
export function closeModal(modalShowFunc) {
  modalShowFunc(false)
  setTimeout(() => {scrollTo(0, 0)}, 0)
}
/**
 * Component for SCP faceted search UI
 * showCommonButtons defaults to true
 */
export default function SearchPanel({
  searchOnLoad
}) {
  // Note: This might become  a Higher-Order Component (HOC).
  // This search component is currently specific to the "Studies" tab, but
  // could possibly also enable search for "Genes" and "Cells" tabs.
  const searchState = useContext(StudySearchContext)

  let searchButtons = <></>
  let downloadButtons = <></>

  searchButtons = <FacetsPanel/>
  downloadButtons = <DownloadButton searchResults={searchState.results}/>

  useEffect(() => {
    // if a search isn't already happening, and searchOnLoad is specified, perform one
    if (!searchState.isLoading && !searchState.isLoaded && searchOnLoad) {
      searchState.performSearch()
    }
  })

  const keywordPrompt = searchState.params.preset === 'covid19' ? 'Search COVID-19 studies' : undefined
  return (
    <div id='search-panel' style={{ display: 'flex' }}>
      { searchButtons }
      <KeywordSearch keywordPrompt={keywordPrompt}/>
      { downloadButtons }
    </div>
  )
}
