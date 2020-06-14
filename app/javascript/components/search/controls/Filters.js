import React from 'react'
import FilterSlider from './FilterSlider'
import _remove from 'lodash/remove'
/**
 * Component for a list of checkbox filters, e.g. disease, species
 */
function FilterCheckboxes(props) {
  function updateSelection(filterId, value) {
    const newSelection = props.selection.slice()
    if (value && !newSelection.includes(filterId)) {
      newSelection.push(filterId)
    }
    if (!value) {
      _remove(newSelection, id => {return id === filterId})
    }
    props.setSelection(newSelection)
  }

  return (
    <ul className="facet-filter-list">
      {
        props.filters.map(filter => {
          return (
            <li key={`li-${filter.id}`}>
              <label htmlFor={filter.id}>
                <input
                  type='checkbox'
                  aria-label='checkbox'
                  onChange={e => {updateSelection(filter.id, e.target.checked)}}
                  id={filter.id}
                  name={filter.id}
                  checked={props.selection.includes(filter.id)}
                />
                <span>{filter.name}</span>
              </label>
            </li>
          )
        })
      }
    </ul>
  )
}

/**
 * Component for filter list and filter slider
 */
export default function Filters(props) {
  const filters = props.filters
  if (props.facet.type !== 'number') {
    return (
      <FilterCheckboxes
        filters={filters}
        setSelection={props.setSelection}
        selection={props.selection}
      />
    )
  } else {
    return (
      <FilterSlider
        facet={props.facet}
        setSelection={props.setSelection}
        selection={props.selection}
      />
    )
  }
}
