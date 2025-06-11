import React, { useState } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faWrench } from '@fortawesome/free-solid-svg-icons'
import { Popover, OverlayTrigger } from 'react-bootstrap'

export default function OptionsControl({searchState}) {
  const [isChecked, setIsChecked] = useState(false)
  const [showOptions, setShowOptions] = useState(false)

  function toggleExternal(checked) {
    const newExternal = checked ? 'hca' : null
    setIsChecked(checked)
    searchState.updateSearch({ external: newExternal })
  }

  const optionsContent = <Popover data-analytics-name='search-options-popover'
                                  id='search-options-popover'>
    <ul className='facet-filter-list'>
      <li>
          <input type="checkbox" checked={isChecked} onChange={() => {toggleExternal(!isChecked)}} />
          Include HCA results
      </li>
    </ul>
  </Popover>

  const optionsButton = <OverlayTrigger
    trigger={['click']}
    placement='bottom'
    animation={false}
    overlay={optionsContent}>
    <button type="button" id="options-button" className="btn btn-default" aria-label='Options'>
      <span><FontAwesomeIcon icon={faWrench} className='icon-left' /> Options</span>
    </button>
  </OverlayTrigger>

  return (
    <span style={{ 'marginLeft': 'auto' }} > {optionsButton} </span>
  )
}
