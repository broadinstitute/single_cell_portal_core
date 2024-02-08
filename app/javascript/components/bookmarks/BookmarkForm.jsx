import { Popover, OverlayTrigger } from 'react-bootstrap'
import { createBookmark } from '~/lib/scp-api'
import React, { useEffect, useState } from 'react'
import Button from 'react-bootstrap/lib/Button'
import _cloneDeep from 'lodash/clone'
import { isUserLoggedIn } from '~/providers/UserProvider'
import { useLocation } from '@reach/router'

export default function BookmarkForm({bookmarks}) {
  const location = useLocation()
  const [errorMessage, setErrorMessage] = useState(null)
  const [allBookmarks, setAllBookmarks] = useState(bookmarks)
  const [savedBookmark, setSavedBookmark] = useState(null)
  const DEFAULT_BOOKMARK = {
    path: getBookmarkPath()
  }
  const [formState, setFormState] = useState(DEFAULT_BOOKMARK)

  // determine if the current view has been bookmarked
  function canSaveBookMark() {
    const existingBookmark = allBookmarks.find(bookmark => {
      return bookmark.link === getBookmarkPath()
    })
    if (existingBookmark) {
      setSavedBookmark(existingBookmark)
    }
  }
  canSaveBookMark()

  function addBookmarkToList(bookmark) {
    console.log('addBookmarkToList')
    const userBookmarks = _cloneDeep(allBookmarks)
    userBookmarks.append(bookmark)
    setAllBookmarks(userBookmarks)
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
    setSavedBookmark(null)
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
    createBookmark(formState).then(bookmark => {
      setSavedBookmark(bookmark)
      addBookmarkToList(bookmark)
    }).catch(error => {
      setSavedBookmark(null)
      if (error.errors) {
        const message = formatErrorMessages(error.errors)
        setErrorMessage(message)
      } else {
        setErrorMessage('server error')
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
    <p><a data-toggle='tooltip' data-original-title={savedBookmark?.path}>This view</a> has been bookmarked</p>
  </Popover>

  const bookmarkForm = <Popover id='bookmark-form-popover'>
    <form id='bookmark-form' onSubmit={handleSaveBookmark}>
      { errorMessage &&
        <div id='bookmark-errors' className='bs-callout bs-callout-danger'>
          <p className='text-danger'>Failed to save bookmark: {errorMessage}</p>
        </div>
      }
      <div className="form-group">
        <label htmlFor='bookmark-name'>Name</label>&nbsp;
        <br/>
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

  const starClass = savedBookmark ? 'fas' : 'far'
  const triggerOverlay = savedBookmark ? savedPopover : bookmarkForm

  return (
    <OverlayTrigger trigger={['click']} rootClose placement="left"
                    overlay={isUserLoggedIn() ? triggerOverlay : loginPopover}>
    <span className={`fa-lg action ${starClass} fa-star`} />
  </OverlayTrigger>
  )
}
