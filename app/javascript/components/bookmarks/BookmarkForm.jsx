import { Popover, OverlayTrigger } from 'react-bootstrap'
import { createBookmark, updateBookmark, deleteBookmark } from '~/lib/scp-api'
import React, { useEffect, useState, useRef } from 'react'
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
  const [bookmarkSaved, setBookmarkSaved] = useState(null)
  const [deleteDisabled, setDeleteDisabled] = useState(null)
  const { ErrorComponent, setShowError, setError } = useErrorMessage()
  const DEFAULT_BOOKMARK = {
    name: '',
    description: '',
    path: getBookmarkPath()
  }
  const overlayRef = useRef('overlay')

  /** copies the url to the clipboard */
  function copyLink() {
    navigator.clipboard.writeText(location.href)
  }

  /** Find a matching bookmark using the current URL params, or return default empty bookmark  */
  function findExistingBookmark() {
    const bookmark = allBookmarks.find(bookmark => { return bookmark.path === getBookmarkPath() })
    if (bookmark) {
      setBookmarkSaved(true)
      return bookmark
    } else {
      setBookmarkSaved(false)
      return DEFAULT_BOOKMARK
    }
  }

  const [currentBookmark, setCurrentBookmark] = useState(findExistingBookmark)

  /** get bookmark ID from BSON object */
  function getBookmarkId(bookmark) {
    return bookmark?._id || bookmark?.id
  }

  /** Add a bookmark to the list of user bookmarks, or update ref of existing */
  function updateBookmarkList(bookmark) {
    setBookmarkSaved(true)
    const existingIdx = allBookmarks.findIndex(bookmark => { return bookmark.path === getBookmarkPath() })
    if (existingIdx >= 0) {
      setAllBookmarks(prevBookmarks => {
        prevBookmarks[existingIdx] = bookmark
        return prevBookmarks
      })
    } else {
      setAllBookmarks(prevBookmarks => [...prevBookmarks, bookmark])
    }

    setCurrentBookmark(bookmark)
  }

  /** remove a deleted bookmark from the list */
  function removeBookmarkFromList(bookmarkId) {
    const remainingBookmarks = allBookmarks.filter(bookmark => {
      return getBookmarkId(bookmark) !== bookmarkId
    })
    setAllBookmarks(remainingBookmarks)
    setBookmarkSaved(false)
    setCurrentBookmark(DEFAULT_BOOKMARK)
  }

  /** concatenate URL parts into string for saving */
  function getBookmarkPath() {
    return `${location.pathname}${location.search}`
  }

  /** reset form state after changing view or creating/deleting bookmarks */
  function resetForm() {
    setShowError(false)
    setCurrentBookmark(findExistingBookmark())
  }

  /** whenever the user changes a cluster/annotation, reset the bookmark form with the current URL params */
  useEffect(() => {
    resetForm()
  }, [location.pathname, location.search])

  /** convenience handler for performing formState updates */
  function handleFormUpdate(event) {
    const value = event.target.value
    const fieldName = event.target.id.split('-')[1]
    let update = {}
    update[fieldName] = value
    setCurrentBookmark(prevBookmark => {
      const newFormState = _cloneDeep(prevBookmark)
      Object.assign(newFormState, update)
      return newFormState
    })
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

  /** show contextual errors */
  function handleErrorContent(error) {
    const errorMessage = formatErrorMessages(error)
    setError(errorMessage)
    setShowError(true)
  }

  /** format errors object into comma-delimited message */
  function formatErrorMessages(error) {
    if (error.errors) {
      return Object.keys(error.errors).map(key => {
        return `${key} ${errors[key][0]}`
      }).join(', ')
    } else {
      return error.message
    }
  }

  /** create/update a new bookmark */
  async function handleSaveBookmark(e) {
    e.preventDefault()
    enableSaveButton(false)
    const saveProps = [currentBookmark]
    const saveFunc = bookmarkSaved ? updateBookmark : createBookmark
    if (bookmarkSaved) {
      saveProps.unshift(getBookmarkId(currentBookmark))
    }
    try {
      const bookmark = await saveFunc(...saveProps)
      overlayRef.current.handleHide()
      enableSaveButton(true)
      setShowError(false)
      resetForm()
      updateBookmarkList(bookmark)
    } catch (error) {
      enableSaveButton(true)
      handleErrorContent(error)
    }
  }

  /** delete a bookmark */
  async function handleDeleteBookmark(e) {
    e.preventDefault()
    setDeleteDisabled(true)
    const toDelete = getBookmarkId(currentBookmark)
    if (!toDelete) {
      setDeleteDisabled(false)
      return false
    } else {
      try {
        await deleteBookmark(toDelete)
        setDeleteDisabled(false)
        setShowError(false)
        overlayRef.current.handleHide()
        removeBookmarkFromList(toDelete)
      } catch (error) {
        setDeleteDisabled(false)
        handleErrorContent(error)
      }
    }
  }

  const loginPopover = <Popover id='login-bookmark-popover' container='body'>
    <span className='action far-lg fa-star'
          data-toggle='tooltip'
          data-original-title='You must sign in to bookmark this view'
          data-placement='left'
    />
  </Popover>
  const bookmarkForm = <Popover id='bookmark-form-popover'>
    <form id='bookmark-form' onSubmit={handleSaveBookmark}>
      { ErrorComponent }
      <div className="form-group">
        <label htmlFor='bookmark-name'>Bookmark name</label>&nbsp;
        <br/>
        <input className="form-control"
               type="text"
               id='bookmark-name'
               value={currentBookmark.name}
               onChange={handleFormUpdate}
        />
      </div>
      <div className="form-group">
      <label htmlFor='bookmark-description'>Description</label><br/>
        <textarea className="form-control"
               id='bookmark-description'
               value={currentBookmark.description}
               onChange={handleFormUpdate}
        />
      </div>
      <div className="form-group">
      <button
          type="button"
          className="btn btn-primary"
          aria-label="Save"
          data-analytics-name="bookmark-submit"
          disabled={saveDisabled}
          onClick={handleSaveBookmark}
      >{saveText}</button>
      { bookmarkSaved &&
        <button
          type="button"
          className="btn btn-danger pull-right"
          aria-label="Delete"
          data-analytics-name="bookmark-delete"
          disabled={deleteDisabled}
          onClick={handleDeleteBookmark}
        >Remove</button>
      }
    </div>
    </form>
  </Popover>

  const starClass = bookmarkSaved ? 'fas' : 'far'

  return <>
    <button className="action action-with-bg"
            onClick={clearExploreParams}
            title="Reset all view options"
            data-analytics-name="explore-view-options-reset">
      <FontAwesomeIcon icon={faUndo}/> Reset view</button>
    <button onClick={copyLink}
            className="action action-with-bg margin-extra-right"
            data-toggle="tooltip"
            title="Copy a link to this visualization to the clipboard">
      <FontAwesomeIcon icon={faLink}/> Get link</button>
    <OverlayTrigger trigger={['click']} rootClose placement="left" ref={overlayRef} animation={false}
                    overlay={isUserLoggedIn() ? bookmarkForm : loginPopover}>
      <span className={`fa-lg action ${starClass} fa-star`} data-analytics-name='bookmark-view'
            title='Bookmark this view'
      />
    </OverlayTrigger>
  </>
}
