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
    <li id={`options-control-${searchProp}`} key={`options-control-${searchProp}`}>
      <label>
        <input type="checkbox" checked={isChecked} onChange={() => {toggleCheckbox(!isChecked)}}/>
          <span onClick={() => {toggleCheckbox(!isChecked)}} >{ label }</span>
      </label>
    </li>
  )
}
