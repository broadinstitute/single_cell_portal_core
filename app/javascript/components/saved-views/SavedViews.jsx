import React, { useState } from 'react'
import { Popover, OverlayTrigger } from 'react-bootstrap'
import { fetchUserSavedViews, createUserSavedView, updateUserSavedView, deleteUserSavedView } from '~/lib/scp-api'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faBookReader } from '@fortawesome/free-solid-svg-icons'
import LoadingSpinner from '~/lib/LoadingSpinner'

export default function SavedViews() {
  const [savedViews, setSavedViews] = useState([])
  const [showSavedViews, setShowSavedViews] = useState(false)

  async function loadSavedViews() {
    const views = await fetchUserSavedViews()
    setSavedViews(views)
    setShowSavedViews(true)
  }

  const overlay = <Popover id='user-saved-views' className='tooltip-wide'>
    <dl>
      {savedViews.map(view => {
        return <div className='saved-view-entry' key={view._id}>
          <dt><a href={view.path}>{view.name}</a></dt>
          <dd>{view.description}</dd>
        </div>
      })}
    </dl>
  </Popover>



  const myViews = <span className='saved-view-list'>
    <button id='my-views' className='btn btn-sm btn-default' onClick={loadSavedViews}>
      <FontAwesomeIcon className="fa-lg" icon={faBookReader}/>
    </button>
    <button id='bookmark' className='btn btn-sm btn-default'>
      <span className="fa-lg far fa-bookmark"></span>
    </button>
  </span>

  const spinner = <Popover id='loading-saved-views' className='tooltip-wide'>
    <span>Loading... <LoadingSpinner testId='saved-views-spinner' /></span>
  </Popover>

  return <OverlayTrigger rootClose trigger={['click']} placement='left'
                         overlay={showSavedViews ? overlay : spinner}>
    { myViews }
  </OverlayTrigger>
}
