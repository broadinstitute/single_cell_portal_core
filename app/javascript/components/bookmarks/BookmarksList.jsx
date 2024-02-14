import React from 'react'
import { Modal } from 'react-bootstrap'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { navigate } from '@reach/router'
import { log } from '~/lib/metrics-api'

export default function BookmarksList({serverBookmarks, serverBookmarksLoaded, studyAccession, showModal, toggleModal}) {

  /** determine whether to reload study or not when selecting bookmark */
  function loadBookmark(bookmark) {
    toggleModal()
    if (bookmark.study_accession === studyAccession) {
      navigate(bookmark.path)
    } else {
      window.location = bookmark.path
    }
    log('load-bookmark')
  }
  return <Modal id='bookmarks-list-modal' data-testid='bookmarks-list-modal' className='modal fade' show={showModal}>
    <Modal.Header><h4>My Bookmarks</h4></Modal.Header>
    <Modal.Body>
      <div id='bookmarks-list-wrapper'>
        {!serverBookmarksLoaded && <>Loading bookmarks... <LoadingSpinner /></>}
        {serverBookmarksLoaded && serverBookmarks.length === 0 &&
          <p className='scp-help-text'>You do not have any saved bookmarks</p>
        }
        {serverBookmarksLoaded && serverBookmarks.length > 0 && serverBookmarks.map(bookmark => {
          return <div key={bookmark._id} className='bookmarks-list-item'>
            <span className='action'
                  data-analytics-name='load-bookmark'
                  onClick={() => {loadBookmark(bookmark)}}
                  data-toggle='tooltip'
                  data-original-title={bookmark.path}
            ><strong>{bookmark.name}</strong></span> <em>{bookmark.study_accession}</em><br/>
            {bookmark.description}
          </div>
        })}

      </div>
    </Modal.Body>
    <Modal.Footer>
      <button type="button"
              className="btn btn-default"
              onClick={toggleModal}
      >Close</button>
    </Modal.Footer>
  </Modal>
}
