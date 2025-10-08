import React, { useState, useContext } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faCogs } from '@fortawesome/free-solid-svg-icons'
import { Popover, OverlayTrigger } from 'react-bootstrap'
import { StudySearchContext } from '~/providers/StudySearchProvider'

import OptionsControl from '~/components/search/controls/OptionsControl'

export default function OptionsButton() {
  const searchContext = useContext(StudySearchContext)
  const [showOptions, setShowOptions] = useState(false)
  const configuredOptions = [
    { searchProp: 'external', value: 'hca', label: 'Include HCA results' },
    { searchProp: 'data_types', value: 'raw_counts', label: 'Has raw counts', multiple: true },
    { searchProp: 'data_types', value: 'diff_exp', label: 'Has differential expression', multiple: true },
    { searchProp: 'data_types', value: 'spatial', label: 'Has spatial data', multiple: true }
  ]

  const optionsPopover = <Popover data-analytics-name='search-options-menu' id='search-options-menu'>
    <ul className="facet-filter-list">
      {
        configuredOptions.map((option, index) => {
        return <OptionsControl
          key={`${option.searchProp}-${index}`}
          searchContext={searchContext}
          searchProp={option.searchProp}
          value={option.value}
          label={option.label}
          multiple={option.multiple}
        />
        })
      }
    </ul>
  </Popover>

  return (
    <OverlayTrigger trigger={['click']} placement='bottom' animation={false} overlay={optionsPopover}>
    <span id="search-options-button" data-testid="search-options-button"
          className={`facet ${showOptions ? 'active' : ''}`}>
      <a onClick={() => setShowOptions(!showOptions)}>
        <FontAwesomeIcon className="icon-left" icon={faCogs}/>Options
      </a>
    </span>
    </OverlayTrigger>
  )
}
