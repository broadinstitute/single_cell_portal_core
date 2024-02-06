import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faStar } from '@fortawesome/free-solid-svg-icons'
import { Popover, OverlayTrigger } from 'react-bootstrap'
import { createUserBookmark, updateUserBookmark, deleteUserBookmark } from '~/lib/scp-api'
import React from 'react'
import Button from 'react-bootstrap/lib/Button'

export default function BookmarkForm(savedView) {
  const NEW_BOOKMARK = {
    name: '',
    description: ''
  }
  const bookmark = <button id='my-views' className='btn btn-sm btn-default' onClick={}>
    <FontAwesomeIcon className="fa-lg" icon={faStar}/>
  </button>

  function getNewViewPath() {
    return `${window.location.pathname}${window.location.search}${window.location.hash}`
  }

  function handleSaveBookmark(e) {
    e.preventDefault()
  }

  return <form id='bookmark-form' onSubmit={handleSaveBookmark}>
    <div className="form-group row">
      <label htmlFor='bookmark-name'>Name</label><br/>
      <input className="form-control"
             type="text"
             id='bookmark-name'
             value={savedView?.name || ''}
      />
      <label htmlFor='bookmark-description'>Description</label><br/>
      <input className="form-control"
             type="text"
             id='bookmark-description'
             value={savedView?.description || ''}

      />
      <input id="bookmark-path"
             type="text"
             disabled="disabled"
             value={savedView?.path || getNewViewPath()}
      />
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
}
