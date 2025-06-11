import React, { useState } from 'react'

export default function OptionsControl({searchContext, searchProp, value, label}) {
  const defaultChecked = searchContext.params[searchProp] === value
  const [isChecked, setIsChecked] = useState(defaultChecked)

  /** toggle state of checkbox */
  function toggleCheckbox(checked) {
    setIsChecked(checked)
    searchContext.updateSearch({ [searchProp] : checked ? value : null })
  }

  return (
    <span className={`facet option-control ${isChecked ? 'active' : ''}` } id={`options-control-${searchProp}`}>
      <a>
        <input type="checkbox" checked={isChecked} onChange={() => {toggleCheckbox(!isChecked)}}/>
          <span className='inner-label' onClick={() => {toggleCheckbox(!isChecked)}} >{ label }</span>
      </a>
  </span>
  )
}
