import { Popover, OverlayTrigger } from 'react-bootstrap'
import { createBookmark, deleteBookmark } from '~/lib/scp-api'
import React, { useEffect, useState, useRef } from 'react'
import Button from 'react-bootstrap/lib/Button'
import _cloneDeep from 'lodash/clone'
import { isUserLoggedIn } from '~/providers/UserProvider'
import { useLocation } from '@reach/router'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faLink, faUndo, faTimes } from '@fortawesome/free-solid-svg-icons'
import useErrorMessage from '~/lib/error-message'

/**
 * Component to bookmark views in Explore tab, as well as existing link/reset buttons
 *
 * @param bookmarks {Array} existing user bookmark objects
 * @param clearExploreParams
 */
export default function BookmarkForm({bookmarks, clearExploreParams}) {
  const location = useLocation()
  const [allBookmarks, setAllBookmarks] = useState(bookmarks)
  const [saveText, setSaveText] = useState('Save')
  const [saveDisabled, setSaveDisabled] = useState(null)
  const [deleteDisabled, setDeleteDisabled] = useState(null)
  const { ErrorComponent, showError, setShowError, setError } = useErrorMessage()
  const DEFAULT_BOOKMARK = {
    path: getBookmarkPath()
  }
  const [formState, setFormState] = useState(DEFAULT_BOOKMARK)
  const overlayRef = useRef('overlay')

  /** copies the url to the clipboard */
  function copyLink() {
    navigator.clipboard.writeText(location.href)
  }

  /** Find a matching bookmark using the current URL params */
  function findExistingBookmark() {
    return allBookmarks.find(bookmark => { return bookmark.path === getBookmarkPath() })
  }

  const [currentBookmark, setCurrentBookmark] = useState(findExistingBookmark())

  /** get bookmark ID from BSON object */
  function getBookmarkId(bookmark) {
    return bookmark?._id || bookmark?.id
  }

  /** Add a bookmark to the list of user bookmarks */
  function addBookmarkToList(bookmark) {
    setAllBookmarks(prevBookmarks => [...prevBookmarks, bookmark])
  }

  /** remove a deleted bookmark from the list */
  function removeBookmarkFromList(bookmarkId) {
    const newBookmarks = allBookmarks.filter(bookmark => {
      return getBookmarkId(bookmark) !== bookmarkId
    })
    setAllBookmarks(newBookmarks)
  }

  /** concatenate URL parts into string for saving */
  function getBookmarkPath() {
    return `${location.pathname}${location.search}`
  }

  /** reset form state after changing view or creating/deleting bookmarks */
  function resetForm() {
    const reset = { name: '', description: '', path: getBookmarkPath() }
    setShowError(false)
    handleUpdate(reset)
  }

  /** whenever the user changes a cluster/annotation, reset the bookmark form with the current URL params */
  useEffect(() => {
    resetForm()
    setCurrentBookmark(findExistingBookmark())
  }, [location.pathname, location.search])

  /** convenience handler for performing formState updates */
  function handleUpdate(update) {
    setFormState(prevFormState => {
      const newFormState = _cloneDeep(prevFormState)
      Object.assign(newFormState, update)
      return newFormState
    })
  }

  /** handle form updates */
  function updateBookmark(e) {
    const value = e.target.value
    const fieldName = e.target.id.split('-')[1]
    let update = {}
    update[fieldName] = value
    return handleUpdate(update)
  }

  /** set state/text on Save button */
  function enableSaveButton(enabled) {
    if (enabled) {
      setSaveText('Save')
      setSaveDisabled(null)
    } else {
      setSaveText('Saving...')
      setSaveDisabled(true)
    }
  }

  function handleErrorContent(error) {
    const errorMessage = formatErrorMessages(error)
    setError(errorMessage)
    setShowError(true)
  }

  // format errors object into comma-delimited message
  function formatErrorMessages(error) {
    if (error.errors) {
      return Object.keys(error.errors).map(key => {
        return `${key} ${errors[key][0]}`
      }).join(', ')
    } else {
      return error.message
    }
  }

  /** create a new bookmark */
  function handleSaveBookmark(e) {
    e.preventDefault()
    enableSaveButton(false)
    createBookmark(formState).then(bookmark => {
      enableSaveButton(true)
      setShowError(false)
      overlayRef.current.handleHide()
      resetForm()
      addBookmarkToList(bookmark)
      setCurrentBookmark(bookmark)
    }).catch(error => {
      enableSaveButton(true)
      setCurrentBookmark(null)
      handleErrorContent(error)
    })
  }

  /** unbookmark a view */
  function handleDeleteBookmark(e) {
    e.preventDefault()
    setDeleteDisabled(true)
    const toDelete = getBookmarkId(currentBookmark)
    if (!toDelete) {
      setDeleteDisabled(false)
      return false
    } else {
      deleteBookmark(toDelete).then(() => {
        setDeleteDisabled(false)
        setShowError(false)
        overlayRef.current.handleHide()
        removeBookmarkFromList(toDelete)
      }).catch(error => {
        setDeleteDisabled(false)
        handleErrorContent(error)
      })
    }
  }

  const loginPopover = <Popover id='login-bookmark-popover' container='body'>
    <span className='action far-lg fa-star'
          data-toggle='tooltip'
          data-original-title='You must sign in to bookmark this view'
          data-placement='left'
    />
  </Popover>

  const savedPopover = <Popover id='bookmark-saved-popover'>
    This view is bookmarked&nbsp;<Button
      className='btn btn-xs btn-danger'
      id='delete-bookmark'
      aria-label="Delete"
      data-analytics-name="bookmark-delete"
      disabled={deleteDisabled}
      onClick={handleDeleteBookmark}
    ><FontAwesomeIcon icon={faTimes} /></Button>
    { ErrorComponent }
  </Popover>

  const bookmarkForm = <Popover id='bookmark-form-popover'>
    <form id='bookmark-form' onSubmit={handleSaveBookmark}>
      { ErrorComponent }
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
          disabled={saveDisabled}
          onClick={handleSaveBookmark}
        >{saveText}
        </Button>
      </div>
    </form>
  </Popover>

  const starClass = findExistingBookmark() ? 'fas' : 'far'
  const triggerOverlay = findExistingBookmark() ? savedPopover : bookmarkForm

  return <>
    <button className="action action-with-bg"
            onClick={clearExploreParams}
            title="Reset all view options"
            data-analytics-name="explore-view-options-reset">
      <FontAwesomeIcon icon={faUndo}/> Reset view
    </button>
    <button onClick={copyLink}
            className="action action-with-bg margin-extra-right"
            data-toggle="tooltip"
            title="Copy a link to this visualization to the clipboard">
      <FontAwesomeIcon icon={faLink}/> Get link
    </button>
    <OverlayTrigger trigger={['click']} rootClose placement="left" ref={overlayRef} animation={false}
                    overlay={isUserLoggedIn() ? triggerOverlay : loginPopover}>
      <span className={`fa-lg action ${starClass} fa-star`} data-analytics-name='bookmark-view'
            title='Bookmark this view'
      />
    </OverlayTrigger>
  </>
}
