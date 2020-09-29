import React, { useState, useContext } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faTimesCircle } from '@fortawesome/free-solid-svg-icons'

import FiltersBoxSearchable from './FiltersBoxSearchable'
import { StudySearchContext } from 'providers/StudySearchProvider'
import { getDisplayNameForFacet } from 'providers/SearchFacetProvider'
import { SearchSelectionContext, getSelectionForFacet } from 'providers/SearchSelectionProvider'
import { withErrorBoundary } from 'lib/ErrorBoundary'
import useCloseableModal from 'hooks/closeableModal'
import _kebabCase from 'lodash/kebabCase'

/**
 * Button for facets, and associated functions
 */
function RawFacetControl({ facet }) {
  const [showFilters, setShowFilters] = useState(false)

  const facetName = facet.name
  const facetId = `facet-${_kebabCase(facetName)}`
  const searchContext = useContext(StudySearchContext)
  const appliedSelection = searchContext.params.facets[facet.id]
  const selectionContext = useContext(SearchSelectionContext)
  const selection = getSelectionForFacet(facet, selectionContext)


  let selectedFilterString
  if (appliedSelection && appliedSelection.length) {
    const selectedFilters =
      facet.filters.filter(filter => appliedSelection.includes(filter.id))
    if (selectedFilters.length > 1) {
      selectedFilterString = `${facetName} (${selectedFilters.length})`
    } else if (selectedFilters.length === 1) {
      selectedFilterString = selectedFilters[0].name
    } else {
      // it's a numeric range filter
      selectedFilterString = `${getDisplayNameForFacet(facet.id)}:
                              ${appliedSelection[0]}-${appliedSelection[1]}
                              ${appliedSelection[2]}`
    }
  }

  /**
    * Clear the selection and update search results
    */
  function clearFacet() {
    selectionContext.updateFacet(facet.id, [], true)
  }

  const { node, clearNode, handleButtonClick } = useCloseableModal(showFilters, setShowFilters)

  let controlContent = getDisplayNameForFacet(facet.id)
  if (selectedFilterString) {
    controlContent =
      <>
        {selectedFilterString }
        <button
          ref={clearNode}
          className='facet-clear'
          onClick={clearFacet}
        >
          <FontAwesomeIcon icon={faTimesCircle}/>
        </button>
      </>
  }

  return (
    <span ref={node}
      id={facetId}
      className={`facet ${showFilters ? 'active' : ''} ${selectedFilterString ? 'selected' : ''}`} // eslint-disable-line max-len
    >
      <a onClick={handleButtonClick}>
        { controlContent }
      </a>
      <FiltersBoxSearchable
        show={showFilters}
        facet={facet}
        setShow={setShowFilters}
        selection={selection}
        setSelection={selection =>
          selectionContext.updateFacet(facet.id, selection)
        }/>
    </span>
  )
}

const FacetControl = withErrorBoundary(RawFacetControl)
export default FacetControl
