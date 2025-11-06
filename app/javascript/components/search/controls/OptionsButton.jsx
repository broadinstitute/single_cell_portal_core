import React, { useState, useContext } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faCogs, faTimesCircle } from '@fortawesome/free-solid-svg-icons'
import { StudySearchContext } from '~/providers/StudySearchProvider'

import OptionsControl from '~/components/search/controls/OptionsControl'
import useCloseableModal from '~/hooks/closeableModal'

/** list of configured search option entries */
export const configuredOptions = [
  { searchProp: 'external', value: 'hca', label: 'Include HCA results' },
  { searchProp: 'data_types', value: 'raw_counts', label: 'Has raw counts', multiple: true },
  { searchProp: 'data_types', value: 'diff_exp', label: 'Has differential expression', multiple: true },
  { searchProp: 'data_types', value: 'spatial', label: 'Has spatial data', multiple: true }
]

/** Search options button for filtering results by data types/sources */
export default function OptionsButton() {
  const searchContext = useContext(StudySearchContext)
  const [showOptions, setShowOptions] = useState(false)

  /** determine if any options have been selected */
  function searchOptionSelected() {
    const opts = []
    configuredOptions.map(option => {
      const opt = option.searchProp
      if (searchContext.params[opt] && searchContext.params[opt].length > 0) {
        opts.push(opt)
      }
    })
    return opts.length > 0
  }

  /** clear all selected options */
  function clearAllOptions() {
    const existingParams = searchContext.params
    configuredOptions.map(option => {delete existingParams[option.searchProp]})
    searchContext.updateSearch(existingParams)
    setShowOptions(false)
  }

  const { node, clearNode, handleButtonClick } = useCloseableModal(showOptions, setShowOptions)

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
    { showOptions && searchOptionSelected() &&
      <a className='pull-right' onClick={clearAllOptions}>
        Clear&nbsp;
        <span
          ref={clearNode}
          data-testid='clear-search-options'
          onClick={clearAllOptions}
          aria-label='Clear options'
        >
          <FontAwesomeIcon icon={faTimesCircle}/>
        </span>
      </a>
    }
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
      { showOptions && optionsMenu }
    </span>
  )
}
