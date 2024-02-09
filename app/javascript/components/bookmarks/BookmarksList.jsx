import React from 'react'
import { Modal } from 'react-bootstrap'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { navigate } from '@reach/router'

export default function BookmarksList({serverBookmarks, serverBookmarksLoaded, showModal, toggleModal}) {
  function loadBookmark(bookmark) {
    navigate(bookmark.path)
  }
  return <Modal id='bookmarks-list-modal' className='modal fade' show={showModal}>
    <Modal.Header><h4>My Bookmarks</h4></Modal.Header>
    <Modal.Body>
      <div id='bookmarks-list-wrapper'>
        { serverBookmarksLoaded && serverBookmarks.map(bookmark => {
          return <div key={bookmark.id} className='bookmarks-list-item'>
            <span className='action'
                  onClick={() => {loadBookmark(bookmark)}}
            >{bookmark.name}</span><br/>
            {bookmark.description}
          </div>
        })}
        { !serverBookmarksLoaded && <>Loading bookmarks... <LoadingSpinner /></>}
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
