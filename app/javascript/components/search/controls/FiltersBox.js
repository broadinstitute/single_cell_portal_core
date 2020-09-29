import React, { useContext } from 'react'
import Button from 'react-bootstrap/lib/Button'

import { StudySearchContext, getAppliedParamsForFacet } from 'providers/StudySearchProvider'
import { SearchSelectionContext, isFacetApplicable } from 'providers/SearchSelectionProvider'
import Filters from './Filters'


// To consider: Get opinions, perhaps move to a UI code style guide.
//
// Systematic, predictable IDs help UX research and UI development.
//
// Form of IDs: <general name> <specific name(s)>
// General name: All lowercase, specified in app code (e.g. 'apply-facet')
// Specific name(s): Cased as specified in API (e.g. 'NCBITaxon_9606')
//
// UI code concatenates names in the ID.  Names in ID are hyphen-delimited.
//
// Examples:
//   * apply-facet-species (for calls-to-action use ID: <action> <component>)
//   * filter-species-NCBITaxon_9606

/**
 * Component that can be clicked to unselect filters
 */
export function ClearFilters({ facetId, onClick }) {
  return (
    <span
      id={`clear-filters-${facetId}`}
      className='clear-filters'
      onClick={onClick}
    >
      CLEAR
    </span>
  )
}

/**
 * Component for the "APPLY" button that can be clicked it to save selected
 * filters for the current facet or facet accordion.
 */
export function ApplyButton({ facetId, isActive, onClick }) {
  return (
    <Button
      id={`apply-filters-box-${facetId}`}
      bsStyle='primary'
      className={`facet-apply-button ${isActive ? 'active' : 'disabled'}`}
      onClick={onClick}
    >
    APPLY
    </Button>
  )
}


/**
 * Component for filter lists that have Apply and Clear
 * We should revisit this structure if we ever have to add a
 * type of control besides filter list and slider
 * Currently, FiltersBox has to own a lot of logic about canApply and applyClick
 * handling that is probably better encapsulated in the individual controls
 */
export default function FiltersBox({ facet, selection, setSelection, filters, setShow, hideControls }) {
  const searchContext = useContext(StudySearchContext)
  const selectionContext = useContext(SearchSelectionContext)

  const appliedSelection = getAppliedParamsForFacet(facet, searchContext)
  const canApply = isFacetApplicable(facet, selectionContext, searchContext)
  const showClear = selection.length > 0

  const facetId = facet.id

  /**
   * Update search context with applied facets upon clicking "Apply"
   */
  function handleApplyClick() {
    if (!canApply) return
    if (facet.type === 'number' &&
        appliedSelection.length === 0 &&
        selection.length === 0) {
      // case where a user clicks apply without changing the slider
      const defaultSelection = [
        facet.min,
        facet.max,
        facet.unit
      ]
      selectionContext.updateFacet(facet.id, defaultSelection, true)
    } else {
      selectionContext.performSearch()
    }
    if (setShow) {
      setShow(false)
    }
  }

  /** clears any selected filters */
  function clearFilters() {
    setSelection([])
  }

  return (
    <div id={`apply-filters-${facetId}`}>
      <Filters
        facet={facet}
        filters={filters}
        selection={selection}
        setSelection={setSelection}
      />
      { !hideControls &&
        <div className='filters-box-footer'>
          {showClear &&
          <ClearFilters
            facetId={facet.id}
            onClick={clearFilters}
          />
          }
          <ApplyButton
            facetId={facetId}
            isActive={canApply}
            onClick={handleApplyClick}
          />
        </div>
      }
    </div>
  )
}
