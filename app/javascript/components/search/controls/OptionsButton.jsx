import React, { useState, useContext } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faCogs } from '@fortawesome/free-solid-svg-icons'
import { StudySearchContext } from '~/providers/StudySearchProvider'

import OptionsControl from '~/components/search/controls/OptionsControl'
import useCloseableModal from '~/hooks/closeableModal'

export default function OptionsButton() {
  const searchContext = useContext(StudySearchContext)
  const [showOptions, setShowOptions] = useState(false)
  const configuredOptions = [
    { searchProp: 'external', value: 'hca', label: 'Include HCA results' },
    { searchProp: 'data_types', value: 'raw_counts', label: 'Has raw counts', multiple: true },
    { searchProp: 'data_types', value: 'diff_exp', label: 'Has differential expression', multiple: true },
    { searchProp: 'data_types', value: 'spatial', label: 'Has spatial data', multiple: true }
  ]

  const { node, _, handleButtonClick } = useCloseableModal(showOptions, setShowOptions)

  const optionsMenu = <div data-analytics-name='search-options-menu' id='search-options-menu'>
    <ul>
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
  </div>

  return (
    <span
      ref={node}
      id="search-options-button"
      data-testid="search-options-button"
      className={`facet ${showOptions ? 'active' : ''}`}
    >
      <a onClick={handleButtonClick}>
        <FontAwesomeIcon className="icon-left" icon={faCogs}/>Options
      </a>
      { showOptions && optionsMenu}
    </span>
  )
}
