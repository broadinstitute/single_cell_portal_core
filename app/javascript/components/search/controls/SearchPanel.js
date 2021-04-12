import React, { useContext, useEffect, useState } from 'react'
import { faQuestionCircle } from '@fortawesome/free-solid-svg-icons'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import Modal from 'react-bootstrap/lib/Modal'

import KeywordSearch from './KeywordSearch'
import FacetsPanel from './FacetsPanel'
import DownloadButton from './DownloadButton'
import DownloadProvider from 'providers/DownloadProvider'
import { StudySearchContext } from 'providers/StudySearchProvider'
import { SearchSelectionContext } from 'providers/SearchSelectionProvider'


const helpModalContent = (<div>
  <h4 className="text-center">Advanced Search</h4><br/>
  Single Cell Portal supports searching studies by ontology classifications. For example, you can search on studies that
  have <b>species</b> of <b>&quot;Homo sapiens&quot;</b> or have an <b>organ</b> of <b>&quot;brain&quot;</b>.
  <br/><br/>
    Currently, about 30% of public studies in SCP provide this metadata information.
  <br/><br/>
  For more detailed information, visit
  our <a href="https://github.com/broadinstitute/single_cell_portal/wiki/Search-Studies" target="_blank" rel="noreferrer">wiki</a>.
  <br/>If you are a study creator and would like to provide that metadata for your study to be searchable,
  see our <a href="https://github.com/broadinstitute/single_cell_portal/wiki/Metadata-File#Metadata-powered-Advanced-Search" target="_blank" rel="noreferrer">metadata guide</a>.
</div>)

/**
 * Component for SCP faceted search UI
 * showCommonButtons defaults to true
 */
export default function SearchPanel({
  showCommonButtons,
  advancedSearchDefault,
  keywordPrompt,
  searchOnLoad
}) {
  // Note: This might become  a Higher-Order Component (HOC).
  // This search component is currently specific to the "Studies" tab, but
  // could possibly also enable search for "Genes" and "Cells" tabs.
  const selectionContext = useContext(SearchSelectionContext)
  const searchState = useContext(StudySearchContext)

  const [showSearchHelpModal, setShowSearchHelpModal] = useState(false)

  useEffect(() => {
    // if a search isn't already happening, and searchOnLoad is specified, perform one
    if (!searchState.isLoading && !searchState.isLoaded && searchOnLoad) {
      searchState.performSearch()
    }
  })

  /** helper method as, for unknown reasons, clicking the bootstrap modal auto-scrolls the page down */
  function closeSearchModal() {
    setShowSearchHelpModal(false)
    setTimeout(() => {scrollTo(0, 0)}, 0)
  }

  return (
    <div id='search-panel'>
      <KeywordSearch keywordPrompt={keywordPrompt}/>
      <FacetsPanel/>
      <a className="action advanced-opts"
        onClick={() => setShowSearchHelpModal(true)}
        data-analytics-name="search-help">
        <FontAwesomeIcon icon={faQuestionCircle} />
      </a>
      <DownloadProvider><DownloadButton /></DownloadProvider>
      <Modal
        show={showSearchHelpModal}
        onHide={closeSearchModal}
        animation={false}
        bsSize='large'>
        <Modal.Body className="">
          { helpModalContent }
        </Modal.Body>
        <Modal.Footer>
          <button className="btn btn-md btn-primary" onClick={closeSearchModal}>OK</button>
        </Modal.Footer>
      </Modal>
    </div>
  )
}
