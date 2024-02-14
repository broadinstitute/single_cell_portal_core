import { Popover, OverlayTrigger } from 'react-bootstrap'
import BookmarksList from '~/components/bookmarks/BookmarksList'
import { fetchBookmarks, createBookmark, updateBookmark, deleteBookmark } from '~/lib/scp-api'
import React, { useEffect, useState, useRef } from 'react'
import _cloneDeep from 'lodash/clone'
import { isUserLoggedIn } from '~/providers/UserProvider'
import { useLocation } from '@reach/router'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faLink, faUndo } from '@fortawesome/free-solid-svg-icons'
import useErrorMessage from '~/lib/error-message'

/**
 * Component to bookmark views in Explore tab, as well as existing link/reset buttons
 *
 * @param bookmarks {Array} existing user bookmark objects
 * @param clearExploreParams
 */
export default function BookmarkManager({bookmarks, studyAccession, clearExploreParams}) {
  const location = useLocation()
  const [allBookmarks, setAllBookmarks] = useState(bookmarks)
  const [saveText, setSaveText] = useState('Save')
  const [saveDisabled, setSaveDisabled] = useState(false)
  const [bookmarkSaved, setBookmarkSaved] = useState(null)
  const [deleteDisabled, setDeleteDisabled] = useState(false)
  const { ErrorComponent, setShowError, setError } = useErrorMessage()
  const DEFAULT_BOOKMARK = {
    name: '',
    description: '',
    study_accession: studyAccession,
    path: getBookmarkPath()
  }

  /** copies the url to the clipboard */
  function copyLink() {
    navigator.clipboard.writeText(location.href)
  }

  /** Find a matching bookmark using the current URL params, or return default empty bookmark  */
  function findExistingBookmark() {
    const bookmark = allBookmarks.find(bookmark => bookmark.path === getBookmarkPath())
    if (bookmark) {
      setBookmarkSaved(true)
      return bookmark
    } else {
      setBookmarkSaved(false)
      return DEFAULT_BOOKMARK
    }
  }

  const [currentBookmark, setCurrentBookmark] = useState(findExistingBookmark)

  /** Add a bookmark to the list of user bookmarks, or update ref of existing */
  function updateBookmarkList(bookmark) {
    setBookmarkSaved(true)
    const existingIdx = allBookmarks.findIndex(bookmark => bookmark.path === getBookmarkPath())
    if (existingIdx >= 0) {
      setAllBookmarks(prevBookmarks => {
        prevBookmarks[existingIdx] = bookmark
        return prevBookmarks
      })
    } else {
      setAllBookmarks(prevBookmarks => [...prevBookmarks, bookmark])
    }
    setServerBookmarksLoaded(false)
    setCurrentBookmark(bookmark)
  }

  /** remove a deleted bookmark from the list */
  function removeBookmarkFromList(bookmarkId) {
    const remainingBookmarks = allBookmarks.filter(bookmark => bookmark._id !== bookmarkId)
    setAllBookmarks(remainingBookmarks)
    setBookmarkSaved(false)
    setServerBookmarksLoaded(false)
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
        return `${key} ${error.errors[key][0]}`
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
      saveProps.unshift(currentBookmark._id)
    }
    try {
      const bookmark = await saveFunc(...saveProps)
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
    const toDelete = currentBookmark._id
    if (!toDelete) {
      setDeleteDisabled(false)
      return false
    } else {
      try {
        await deleteBookmark(toDelete)
        setDeleteDisabled(false)
        setShowError(false)
        removeBookmarkFromList(toDelete)
      } catch (error) {
        setDeleteDisabled(false)
        handleErrorContent(error)
      }
    }
  }

  const [serverBookmarks, setServerBookmarks] = useState([])
  const [serverBookmarksLoaded, setServerBookmarksLoaded] = useState(false)
  const [showBookmarksModal, setShowBookmarksModal] = useState(false)

  const toggleBookmarkModal = () => {
    setShowBookmarksModal(!showBookmarksModal)
  }

  /** load all user bookmarks from server */
  async function loadServerBookmarks() {
    toggleBookmarkModal()
    if (!serverBookmarksLoaded) {
      try {
        const serverUserBookmarks = await fetchBookmarks()
        setServerBookmarks(serverUserBookmarks)
        setServerBookmarksLoaded(true)
      } catch (error) {
        setShowBookmarksModal(false)
        setServerBookmarks([])
        setServerBookmarksLoaded(false)
      }
    }
  }

  const loginNotice = <a href='/single_cell/users/auth/google_oauth2' data-method='post'
                         className={`fa-lg action far fa-star`} data-analytics-name='bookmark-login-notice'
                         id='bookmark-login-notice' data-toggle='tooltip' data-placement='left'
                         data-original-title='Click to sign in, then bookmark this view' />

  const formRef = useRef('bookmarkForm')
  const bookmarkForm = <Popover data-analytics-name='bookmark-form-popover' id='bookmark-form-popover'>
    <form id='bookmark-form' onSubmit={handleSaveBookmark}>
      { ErrorComponent }
      <div className="form-group">
        <span className='fa fa-times action bookmark-form-close'
              onClick={() => {formRef.current.handleHide()}}></span>
        <label htmlFor='bookmark-name'>Bookmark name</label>
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
        <label htmlFor='bookmark-study-accession'>Study</label>&nbsp;
        <br/>
        <input className="form-control"
               type="text"
               id='bookmark-study-accession'
               readOnly
               value={studyAccession}
               onChange={handleFormUpdate}
        />
      </div>
      <div className="form-group">
      <button
          type="button"
          className="btn btn-primary"
          aria-label="Save"
          data-analytics-name="submit-bookmark"
          disabled={saveDisabled}
          onClick={handleSaveBookmark}
      >{saveText}</button>
      { bookmarkSaved &&
        <button
          type="button"
          className="btn btn-danger pull-right"
          aria-label="Delete"
          data-analytics-name="delete-bookmark"
          disabled={deleteDisabled}
          onClick={handleDeleteBookmark}
        >Remove</button>
      }
    </div>
    </form>
    <span data-analytics-name='manage-bookmarks'
          data-testid='manage-bookmarks'
          className='action' onClick={loadServerBookmarks}>
      See bookmarks
    </span>
    <BookmarksList serverBookmarks={serverBookmarks}
                   serverBookmarksLoaded={serverBookmarksLoaded}
                   studyAccession={studyAccession}
                   showModal={showBookmarksModal}
                   toggleModal={toggleBookmarkModal}/>
  </Popover>

  const starClass = bookmarkSaved ? 'fas' : 'far'

  return (<div id='bookmark-container'>
    <button className="action action-with-bg"
            onClick={clearExploreParams}
            title="Reset all view options"
            data-analytics-name="explore-view-options-reset">
      <FontAwesomeIcon icon={faUndo}/> Reset view</button>
    <button onClick={copyLink}
            className="action action-with-bg"
            data-toggle="tooltip"
            title="Copy a link to this visualization to the clipboard">
      <FontAwesomeIcon icon={faLink}/> Get link</button>
    { isUserLoggedIn() &&
      <OverlayTrigger trigger={['click']} placement="left" animation={false}
                      overlay={bookmarkForm} ref={formRef}>
      <span className={`fa-lg action ${starClass} fa-star`}
            data-analytics-name='bookmark-manager'
            id='bookmark-manager'
            title='Bookmark this view'
      />
      </OverlayTrigger>
    }
    { !isUserLoggedIn() && loginNotice }
  </div>)
}
