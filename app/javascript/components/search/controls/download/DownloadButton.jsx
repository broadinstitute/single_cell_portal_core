import React, { useState, useContext } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faDownload } from '@fortawesome/free-solid-svg-icons'
import Tooltip from 'react-bootstrap/lib/Tooltip'
import OverlayTrigger from 'react-bootstrap/lib/OverlayTrigger'

import DownloadSelectionModal from './DownloadSelectionModal'
import { UserContext } from '~/providers/UserProvider'

/**
 * Component for "Download" button which shows a Bulk Download modal on click.
 */
export default function DownloadButton({ searchResults={} }) {
  const userContext = useContext(UserContext)
  const [showModal, setShowModal] = useState(false)
  const matchingAccessions = searchResults.matchingAccessions || []

  /**
   * Reports whether Download button should be active,
   * i.e. user is signed in, has search results,
   * and search has parameters (i.e. user would not download all studies)
   * and download context (i.e. download size preview) has loaded
   */
  const active = (
    userContext.accessToken !== '' &&
    matchingAccessions.length > 0 &&
    (searchResults?.terms?.length > 0 || searchResults?.facets?.length > 0)
  )

  const downloadDisabled = !active
  const downloadButton = <button
    style={{ 'pointerEvents': downloadDisabled ? 'none' : 'auto' }}
    type="button"
    id="download-button"
    className="btn btn-primary"
    disabled={downloadDisabled}
    aria-disabled={downloadDisabled}
    aria-label='Download'
    onClick={() => {setShowModal(!showModal)}}>
    <span>
      <FontAwesomeIcon className="icon-left" icon={faDownload}/> Download
    </span>
  </button>

  let hint = 'Download files for your search results'
  if (downloadDisabled) {
    if (userContext.accessToken === '') {
      hint = 'To download, please sign in'
    } else {
      hint = 'To download, first do a search that returns results'
    }
  }
  return (
    <>
      <OverlayTrigger placement='top' overlay={<Tooltip id='download-tooltip'>{hint}</Tooltip>}>
        <span style={{ 'marginLeft': 'auto' }} > {downloadButton} </span>
      </OverlayTrigger>
      { showModal &&
        <DownloadSelectionModal
          show={showModal}
          setShow={setShowModal}
          studyAccessions={matchingAccessions}/> }
    </>
  )
}
