import React, { useState } from 'react'

/** checkbox control for adding optional parameters to search query */
export default function OptionsControl({ searchContext, searchProp, value, label, multiple = false }) {
  const defaultChecked = isDefaultChecked()
  const [isChecked, setIsChecked] = useState(defaultChecked)
  const optionId = `options-control-${searchProp}-${value}`

  /** return existing url query params for this option */
  function getExistingOpts() {
    return searchContext.params[searchProp]?.split(',').filter(o => o !== '') || []
  }

  /** set the default state for this option checkbox */
  function isDefaultChecked() {
    return multiple ? getExistingOpts().includes(value) : searchContext.params[searchProp] === value
  }

  /** toggle state of checkbox */
  function toggleCheckbox(checked) {
    setIsChecked(checked)
    if (multiple) {
      const existingOpts = getExistingOpts()
      const newOpts = checked ? existingOpts.concat(value) : existingOpts.filter(v => v !== value)
      searchContext.updateSearch({ [searchProp] : newOpts.join(',') })
    } else {
      searchContext.updateSearch({ [searchProp] : checked ? value : null })
    }
  }

  return (
    <li id={optionId} key={optionId} onClick={() => {toggleCheckbox(!isChecked)}}>
      <input data-testid={`options-checkbox-${searchProp}-${value}`} type="checkbox" checked={isChecked} readOnly />
      { label }
    </li>
  )
}
