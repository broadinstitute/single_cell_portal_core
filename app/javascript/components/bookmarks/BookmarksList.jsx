import React from 'react'
import { Modal } from 'react-bootstrap'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { navigate } from '@reach/router'

export default function BookmarksList({serverBookmarks, serverBookmarksLoaded, showModal, toggleModal}) {
  const ACCESSION_MATCHER = /SCP\d{1,4}/
  // determine if the requested bookmark is in another study
  function isSameStudy(bookmark) {
    const currentStudy = window.location.pathname.match(ACCESSION_MATCHER)
    const bookmarkStudy = bookmark.path.match(ACCESSION_MATCHER)
    return currentStudy[0] === bookmarkStudy[0]
  }

  function loadBookmark(bookmark) {
    if (isSameStudy(bookmark)) {
      navigate(bookmark.path)
    } else {
      window.location = bookmark.path
    }
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
          return <div key={bookmark.id} className='bookmarks-list-item'>
            <span className='action'
                  onClick={() => {loadBookmark(bookmark)}}
                  data-toggle='tooltip'
                  data-original-title={bookmark.path}
            >{bookmark.name}</span><br/>
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
