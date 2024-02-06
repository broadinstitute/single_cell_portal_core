import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faStar } from '@fortawesome/free-solid-svg-icons'
import { Popover, OverlayTrigger } from 'react-bootstrap'
import { createBookmark, updateBookmark, deleteBookmark } from '~/lib/scp-api'
import React, { useState } from 'react'
import Button from 'react-bootstrap/lib/Button'

export default function BookmarkForm(savedView) {

  function getNewViewPath() {
    return `${window.location.pathname}${window.location.search}${window.location.hash}`
  }

  function handleSaveBookmark(e) {
    e.preventDefault()
  }

  const bookmarkForm = <Popover id='save-bookmark-popover' container='body'>
    <form id='bookmark-form' onSubmit={handleSaveBookmark}>
      <div className="form-group">
        <label htmlFor='bookmark-name'>Name</label><br/>
        <input className="form-control"
               type="text"
               id='bookmark-name'
               value={savedView?.name || ''}
        />
      </div>
      <div className="form-group">
      <label htmlFor='bookmark-description'>Description</label><br/>
        <input className="form-control"
               type="text"
               id='bookmark-description'
               value={savedView?.description || ''}

        />
      </div>
      <div className="form-group">
      <input id="bookmark-path"
             className="form-control"
             type="text"
             value={getNewViewPath()}
        />
      </div>
      <div className="form-group">
      <Button
          type="button"
          className="btn btn-primary"
          aria-label="Save"
          data-analytics-name="bookmark-submit"
          onClick={handleSaveBookmark}
        >Save
        </Button>
      </div>
    </form>
  </Popover>

  return <OverlayTrigger trigger={['click']} rootClose placement="left" overlay={bookmarkForm}>
    <FontAwesomeIcon className="fa-lg action" icon={faStar}/>
  </OverlayTrigger>
}
