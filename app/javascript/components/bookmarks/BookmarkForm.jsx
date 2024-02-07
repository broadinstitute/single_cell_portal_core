import { Popover, OverlayTrigger } from 'react-bootstrap'
import { fetchBookmarks, createBookmark } from '~/lib/scp-api'
import React, { useEffect, useState } from 'react'
import Button from 'react-bootstrap/lib/Button'
import _cloneDeep from 'lodash/clone'
import { isUserLoggedIn } from '~/providers/UserProvider'
import { useLocation } from '@reach/router'

export default function BookmarkForm() {
  const location = useLocation()
  const DEFAULT_BOOKMARK = {
    path: getBookmarkPath()
  }
  const [formState, setFormState] = useState(DEFAULT_BOOKMARK)
  const [errorMessage, setErrorMessage] = useState(null)
  const [allBookmarks, setAllBookmarks] = useState([])
  const [bookmarkSaved, setBookmarkSaved] = useState(false)

  // determine if the current view has been bookmarked
  function canSaveBookMark() {
    fetchBookmarks().then(bookmarks => {
      setAllBookmarks(bookmarks)
    })
    const existingBookmark = allBookmarks.find(bookmark => {
      return bookmark.path === getBookmarkPath()
    })
    if (existingBookmark) {
      setBookmarkSaved(true)
    }
  }

  // concatenate URL parts into string for saving
  function getBookmarkPath() {
    return `${location.pathname}${location.search}${location.hash}`
  }

  useEffect(() => {
    resetForm()
    canSaveBookMark()
  }, [location.search])

  function resetForm() {
    setErrorMessage(null)
    const reset = { name: '', description: '', path: getBookmarkPath() }
    handleUpdate(reset)
  }

  // convenience handler for performing formState updates
  function handleUpdate(update) {
    setBookmarkSaved(false)
    setFormState(prevFormState => {
      const newFormState = _cloneDeep(prevFormState)
      Object.assign(newFormState, update)
      return newFormState
    })
  }

  // handle form updates
  function updateBookmark(e) {
    const value = e.target.value
    const fieldName = e.target.id.split('-')[1]
    let update = {}
    update[fieldName] = value
    return handleUpdate(update)
  }

  // create bookmark
  function handleSaveBookmark(e) {
    e.preventDefault()
    const data = new FormData()
    Object.keys(formState).forEach(key => {
      data.append(key, formState[key])
    })
    createBookmark(data).then(() => {
      setBookmarkSaved(true)
    }).catch(error => {
      setBookmarkSaved(false)
      if (error.errors) {
        const message = formatErrorMessages(error.errors)
        setErrorMessage(message)
      } else {
        setErrorMessage('unknown error')
      }
    })
  }

  // format errors object into comma-delimited message
  function formatErrorMessages(errors) {
    return Object.keys(errors).map(key => {
      return `${key} ${errors[key][0]}`
    }).join(', ')
  }

  const loginPopover = <Popover id='login-bookmark-popover' container='body'>
    <span className='action far-lg fa-star'
          data-toggle='tooltip'
          data-original-title='You must sign in to bookmark this view'
          data-placement='left'
    />
  </Popover>


  const savedPopover = <Popover id='bookmark-saved-popover'>
    <p className='help-block'>This view has been bookmarked</p>
  </Popover>

  const bookmarkForm = <Popover id='bookmark-form-popover'>
    <form id='bookmark-form' onSubmit={handleSaveBookmark}>
      { errorMessage &&
        <div id='bookmark-errors' className='bs-callout bs-callout-danger'>
          <p className='text-danger'>Failed to save bookmark: {errorMessage}</p>
        </div>
      }
      <div className="form-group">
        <label htmlFor='bookmark-name'>Name</label><br/>
        <input className="form-control"
               type="text"
               id='bookmark-name'
               value={formState?.name}
               onChange={updateBookmark}
        />
      </div>
      <div className="form-group">
      <label htmlFor='bookmark-description'>Description</label><br/>
        <textarea className="form-control"
               id='bookmark-description'
               value={formState?.description}
               onChange={updateBookmark}

        />
      </div>
      <div className="form-group">
        <span className='btn btn-small btn-default'
              data-toggle='tooltip'
              data-original-title={formState?.path}
        >
          See bookmark
        </span>
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

  const starClass = bookmarkSaved ? 'fas' : 'far'
  const triggerOverlay = bookmarkSaved ? savedPopover : bookmarkForm

  return (
    <OverlayTrigger trigger={['click']} rootClose placement="left"
                    overlay={isUserLoggedIn() ? triggerOverlay : loginPopover}>
    <span className={`fa-lg action ${starClass} fa-star`} />
  </OverlayTrigger>
  )
}
