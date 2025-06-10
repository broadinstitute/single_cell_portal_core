import React, { useState } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faWrench } from '@fortawesome/free-solid-svg-icons'

export default function OptionsControl({searchState}) {
    const [isChecked, setIsChecked] = useState(false)

    function toggleExternal(checked) {
      const newExternal = checked ? 'hca' : null
      setIsChecked(checked)
      searchState.updateSearch({ external: newExternal })
    }

    return (
      <>
        <span className='search-title'>
          Options&nbsp;
            <FontAwesomeIcon icon={faWrench} className='search-icon' />
        </span>
        <ul className='facet-filter-list'>
          <li>
            <a>
              <input
                type="checkbox"
                checked={isChecked}
                onChange={() => {toggleExternal(!isChecked)}}
              />
              Include HCA results
            </a>
          </li>
        </ul>
      </>
    )
}
