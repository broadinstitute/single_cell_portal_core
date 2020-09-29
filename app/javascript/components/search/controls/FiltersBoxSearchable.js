import React, { useState } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faExternalLinkAlt, faTimesCircle } from '@fortawesome/free-solid-svg-icons'
import pluralize from 'pluralize'
import _find from 'lodash/find'
import _remove from 'lodash/remove'

import { fetchFacetFilters } from 'lib/scp-api'
import FiltersBox from './FiltersBox'
import FiltersSearchBar from './FiltersSearchBar'

/**
 * Component for filter search and filter lists
 */
export default function FiltersBoxSearchable({ facet, selection, setSelection, show, setShow, hideControls }) {
  // State that is specific to FiltersBox
  const [matchingFilters, setMatchingFilters] = useState(facet.filters)
  const [hasFilterSearchResults, setHasFilterSearchResults] = useState(false)

  /*
   * TODO: Get opinions, perhaps move to a UI code style guide.
   *
   * Systematic, predictable IDs help UX research and UI development.
   *
   * Form of IDs: <general name> <specific name(s)>
   * General: All lowercase, specified in app code (e.g. 'apply-facet')
   * Specific: Cased as specified in API (e.g. 'species', 'NCBItaxon9606')
   * UI code concatenates names in the ID.  Names in ID are hyphen-delimited.
   *
   * Examples:
   *   * apply-facet-species (for calls-to-action use ID: <action> <component>)
   *   * filter-species-NCBItaxon9606
   */
  const facetName = facet.name
  const facetId = facet.id
  const componentName = 'filters-box-searchable'
  const componentId = `${componentName}-${facetId}`

  /**
   * Search for filters in this facet that match input text terms
   *
   * For example, among the many filters in the "Disease" facet, search
   * for filters matching the term "tuberculosis".
   */
  async function searchFilters(terms) {
    const apiData = await fetchFacetFilters(facet.id, terms)
    const matchingFilters = apiData.filters
    const hasResults = apiData.query !== '' && matchingFilters.length > 0

    setHasFilterSearchResults(hasResults)

    setMatchingFilters(matchingFilters)
  }

  /**
   * Summarize filters, either default or
   */
  function getFiltersSummary() {
    let filtersSummary = 'Available Filters'

    if (hasFilterSearchResults) {
      const numMatches = matchingFilters.length
      const resultsName = pluralize(facetName, numMatches)
      filtersSummary = `${numMatches} ${resultsName} found`
    }
    return filtersSummary
  }

  /** remove a single filter from the selection */
  function removeFilter(filterId) {
    const newSelections = selection.slice()
    _remove(newSelections, id => {return id === filterId})
    setSelection(newSelections)
  }

  const showSearchBar = facet.links.length > 0 || facet.filters.length > 4
  let selectedFilterBadges = <></>
  if (selection.length && facet.type != 'number') {
    selectedFilterBadges = (
      <div className="filter-badge-list">
        { selection.map(filterId => {
          const matchedFilter = _find(facet.filters, { id: filterId })
          return (
            <span key={filterId}
              className="badge"
              onClick={() => removeFilter(filterId)}>
              {matchedFilter.name} <FontAwesomeIcon icon={faTimesCircle}/>
            </span>
          )
        }) }
      </div>
    )
  }

  return (
    <>
      {
        show && <div className={componentName} id={componentId}>
          { showSearchBar && (
            <>
              <FiltersSearchBar
                filtersBoxId={componentId}
                searchFilters={searchFilters}
              />
              { selectedFilterBadges }
              <div className='filters-box-header'>
                <span className='default-filters-list-name'>
                  {getFiltersSummary()}
                </span>
                <span className='facet-ontology-links'>
                  {
                    facet.links.map((link, i) => {
                      return (
                        <a
                          key={`link-${i}`}
                          href={link.browser_url ? link.browser_url : link.url}
                          target='_blank'
                          rel='noopener noreferrer'
                        >
                          {link.name}&nbsp;&nbsp;
                          <FontAwesomeIcon icon={faExternalLinkAlt}/>
                        </a>
                      )
                    })
                  }
                </span>
              </div>
            </>
          )}
          { !showSearchBar && selectedFilterBadges }
          <FiltersBox
            facet={facet}
            filters={matchingFilters}
            setShow={setShow}
            selection={selection}
            setSelection={setSelection}
            hideControls={hideControls}
          />
        </div>
      }
    </>
  )
}
