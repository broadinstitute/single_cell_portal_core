import React, { useState } from 'react'

/** checkbox control for adding optional parameters to search query */
export default function OptionsControl({ searchContext, searchProp, value, label, multiple = false }) {
  const defaultChecked = searchContext.params[searchProp] === value
  const [isChecked, setIsChecked] = useState(defaultChecked)


  /** toggle state of checkbox */
  function toggleCheckbox(checked) {
    setIsChecked(checked)
    if (multiple) {
      const existingOpts = searchContext.params[searchProp]?.split(',').filter(o => o !== '') || []
      const newOpts = checked ? existingOpts.concat(value) : existingOpts.filter(v => v !== value)
      searchContext.updateSearch({ [searchProp] : newOpts.join(',') })
    } else {
      searchContext.updateSearch({ [searchProp] : checked ? value : null })
    }
  }

  return (
    <li id={`options-control-${searchProp}`} key={`options-control-${searchProp}`}>
      <label>
        <input type="checkbox" checked={isChecked} onChange={() => {toggleCheckbox(!isChecked)}}/>
          <span onClick={() => {toggleCheckbox(!isChecked)}} >{ label }</span>
      </label>
    </li>
  )
}
