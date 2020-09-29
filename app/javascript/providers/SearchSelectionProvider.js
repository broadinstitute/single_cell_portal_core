import React, { useContext, useState } from 'react'
import { StudySearchContext, getAppliedParamsForFacet } from './StudySearchProvider'
import _clone from 'lodash/clone'
import _isEqual from 'lodash/isEqual'

/** The currently selected state of the search panel */
export const SearchSelectionContext = React.createContext({
  terms: '',
  facets: {},
  updateSelection: undefined,
  performSearch: undefined
})

/** returns the currently selected filter ids for the given facet object */
export function getSelectionForFacet(facet, selectionContext) {
  let selection = []
  if (selectionContext.facets[facet.id]) {
    selection = selectionContext.facets[facet.id]
  }
  return selection
}

/** returns whether or not the current selection for the given facet object is different
  * than what the most recently performed search was */
export function isFacetApplicable(facet, selectionContext, searchContext) {
  const selection = getSelectionForFacet(facet, selectionContext)
  const appliedSelection = getAppliedParamsForFacet(facet, searchContext)
  const isSelectionValid = facet.type !== 'number' ||
                            (selection.length === 0 ||
                              !isNaN(parseInt(selection[0])) && !isNaN(parseInt(selection[1])))

  const isApplicable = isSelectionValid &&
                       (!_isEqual(selection, appliedSelection) ||
                       facet.type === 'number' && appliedSelection.length === 0)
                       // allow application of number filters to default range
  return isApplicable
}

/** Renders its children within a SearchSelectionContext provider */
export default function SearchSelectionProvider(props) {
  const searchContext = useContext(StudySearchContext)
  const appliedSelection = _clone(searchContext.params)
  const [selection, setSelection] = useState(
    appliedSelection ?
      appliedSelection :
      { terms: '', facets: {} })
  selection.updateSelection = updateSelection
  selection.updateFacet = updateFacet
  selection.performSearch = performSearch

  /** merges the update into the current selection */
  function updateSelection(value, searchNow) {
    const newSelection = Object.assign({}, selection, value)
    if (searchNow) {
      searchContext.updateSearch(newSelection)
    }
    setSelection(newSelection)
  }

  /** merges the facet update into the current selection */
  function updateFacet(facetId, value, searchNow) {
    const updatedFacet = {}
    updatedFacet[facetId] = value
    const facetObj = Object.assign({}, selection.facets, updatedFacet)
    const newSelection = Object.assign({}, selection)
    newSelection.facets = facetObj
    if (searchNow) {
      searchContext.updateSearch(newSelection)
    }
    setSelection(newSelection)
  }

  /** execute the search on the server */
  function performSearch() {
    searchContext.updateSearch(selection)
  }

  return (
    <SearchSelectionContext.Provider value={selection}>
      { props.children }
    </SearchSelectionContext.Provider>
  )
}
