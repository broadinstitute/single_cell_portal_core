import React, { useContext, useEffect, useState } from 'react'
import { faQuestionCircle } from '@fortawesome/free-solid-svg-icons'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import Modal from 'react-bootstrap/lib/Modal'

import KeywordSearch from './KeywordSearch'
import FacetsPanel from './FacetsPanel'
import DownloadButton from './DownloadButton'
import DownloadProvider from 'providers/DownloadProvider'
import { StudySearchContext } from 'providers/StudySearchProvider'
import { UserContext } from 'providers/UserProvider'
import { SearchSelectionContext } from 'providers/SearchSelectionProvider'

/** render the legacy 'popular' and 'recent' search buttons */
function CommonSearchButtons() {
  const searchState = useContext(StudySearchContext)
  /** update the search params */
  function handleClick(ordering) {
    searchState.updateSearch({ order: ordering })
  }
  return (
    <>
      <span className="facet">
        <a onClick={() => handleClick('popular')}>Most Popular</a>
      </span>
      <span className="facet">
        <a onClick={() => handleClick('recent')}>Most Recent</a>
      </span>
    </>
  )
}

const helpModalContent = (<div>
  <h4 className="text-center">Advanced Search</h4><br/>
  Single Cell Portal supports searching on specific facets of studies by ontology classifications.
  <br/><br/>
   For example, you can search on studies that
  have <b>species</b> of <b>&quot;Homo sapiens&quot;</b> or have an <b>organ</b> of <b>&quot;brain&quot;</b>.
  <br/>
    Currently, about <b>70 out of ~300</b> public studies in SCP provide this metadata information.
  <br/><br/>
  For more detailed information, visit
  our
  <a href="https://github.com/broadinstitute/single_cell_portal/wiki/Search-Studies"
    target="_blank" rel="noreferrer">wiki
  </a>.
  <br/>If you are a study creator and would like to provide that metadata for your study to be searchable,
  see our
  <a href="https://github.com/broadinstitute/single_cell_portal/wiki/Metadata-File#Metadata-powered-Advanced-Search"
    target="_blank" rel="noreferrer">metadata guide
  </a>.
</div>)

/**
 * Component for SCP faceted search UI
 * showCommonButtons defaults to true
 */
export default function SearchPanel({
  advancedSearchDefault,
  searchOnLoad,
  homeParams,
  updateHomeParams,
  clearHomeParams,
  routerLocation,
  homeInfo,
  setHomeInfo
}) {
  // Note: This might become  a Higher-Order Component (HOC).
  // This search component is currently specific to the "Studies" tab, but
  // could possibly also enable search for "Genes" and "Cells" tabs.
  const selectionContext = useContext(SearchSelectionContext)
  const searchState = useContext(StudySearchContext)
  const userState = useContext(UserContext)
  const featureFlagState = userState.featureFlagsWithDefaults
  if (userState.isAnonymous) {
    if (localStorage.getItem('faceted-search-flag') === 'true') {
      featureFlagState.faceted_search = true
    }
  }

  const [showAdvancedSearch, setShowAdvancedSearch] = useState(advancedSearchDefault || featureFlagState.faceted_search)
  const [showSearchHelpModal, setShowSearchHelpModal] = useState(false)
  const [showSearchOptInModal, setShowSearchOptInModal] = useState(false)
  const [isNewToUser, setIsNewToUser] = useState(true)

  let searchButtons = <></>
  let downloadButtons = <></>

  /** pop a modal if first-time click, otherwise just enable the extra filters */
  function handleMoreFiltersClick() {
    if (isNewToUser) {
      setShowSearchOptInModal(true)
    } else {
      setAdvancedSearchEnabled(true)
    }
  }

  let advancedOptsLink = <a className="action advanced-opts" onClick={handleMoreFiltersClick}>
    Advanced Search <sup className="new-feature">BETA</sup>
  </a>
  if (showAdvancedSearch) {
    searchButtons = <FacetsPanel facets={homeInfo ? homeInfo.facets : []} />
    downloadButtons = <DownloadProvider><DownloadButton /></DownloadProvider>
    advancedOptsLink = <a className="action advanced-opts"
      onClick={() => setShowSearchHelpModal(true)}
      data-analytics-name="search-help">
      <FontAwesomeIcon icon={faQuestionCircle} />
    </a>
  } else {
    searchButtons = <CommonSearchButtons/>
  }

  useEffect(() => {
    // if a search isn't already happening, and searchOnLoad is specified, perform one
    if (!searchState.isLoading && !searchState.isLoaded && searchOnLoad) {
      searchState.performSearch()
    }
  })

  /** helper method as, for unknown reasons, clicking the bootstrap modal auto-scrolls the page down */
  function closeModal(modalShowFunc) {
    modalShowFunc(false)
    setTimeout(() => {scrollTo(0, 0)}, 0)
  }

  /** handle enabling/disabling advanced search on the page and syncing the user's feature flags */
  function setAdvancedSearchEnabled(enabled, modalShowFunc) {
    // for signed-in users, update their feature flag, for everyone, save in localStorage
    // this means signed-in users will see advanced search even if they are not signed in, once they
    // opt in

    if (!userState.isAnonymous) {
      userState.updateFeatureFlags({ faceted_search: enabled })
    }
    localStorage.setItem('faceted-search-flag', enabled.toString())
    setShowAdvancedSearch(enabled)
    setIsNewToUser(false)
    if (modalShowFunc) {
      closeModal(modalShowFunc)
    }
    if (enabled) {
      selectionContext.updateSelection({ terms: '' }, true)
    }
  }
  const keywordPrompt = searchState.params.preset === 'covid19' ? 'Search COVID-19 studies' : undefined
  return (
    <div id='search-panel'>
      <KeywordSearch keywordPrompt={keywordPrompt}/>
      { searchButtons }
      { advancedOptsLink }
      { downloadButtons }
      <Modal
        show={showSearchOptInModal}
        onHide={() => closeModal(setShowSearchOptInModal)}
        animation={false}
        bsSize='large'>
        <Modal.Body className="">
          { helpModalContent }
        </Modal.Body>
        <Modal.Footer>
          <button className="btn btn-md btn-primary" onClick={() => {
            setAdvancedSearchEnabled(true, setShowSearchOptInModal)
          }}>Yes, show advanced search</button>
          <button className="btn btn-md" onClick={() => {
            setAdvancedSearchEnabled(false, setShowSearchOptInModal)
          }}>Cancel</button>
        </Modal.Footer>
      </Modal>
      <Modal
        show={showSearchHelpModal}
        onHide={() => closeModal(setShowSearchHelpModal)}
        animation={false}
        bsSize='large'>
        <Modal.Body className="">
          { helpModalContent }
        </Modal.Body>
        <Modal.Footer>
          <button className="btn btn-md btn-primary" onClick={() => {
            setAdvancedSearchEnabled(true, setShowSearchHelpModal)
          }}>Yes, use advanced search</button>
          <button className="btn btn-md" onClick={() => {
            setAdvancedSearchEnabled(false, setShowSearchHelpModal)
          }}>Go back to legacy search</button>
        </Modal.Footer>
      </Modal>
    </div>
  )
}
