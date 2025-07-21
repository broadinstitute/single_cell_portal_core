import React, { useState } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faExternalLinkAlt, faSearch, faTimesCircle } from '@fortawesome/free-solid-svg-icons'
import pluralize from 'pluralize'
import _find from 'lodash/find'
import _remove from 'lodash/remove'

import FiltersBox from './FiltersBox'
import FormControl from 'react-bootstrap/lib/FormControl'
import Button from 'react-bootstrap/lib/Button'

/**
 * Component for filter search and filter lists
 */
export default function FiltersBoxSearchable({ facet, selection, setSelection, show, setShow, hideControls }) {
  // State that is specific to FiltersBox
  const [matchingFilters, setMatchingFilters] = useState(facet.filters)
  const [searchText, setSearchText] = useState('')
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
  function searchFilters(terms) {
    const lcTerms = terms.split(' ').map(text => text.toLowerCase())
    const newFilters = facet.filters.filter(facetFilter => {
      return lcTerms.some(lcTerm => {
        return facetFilter.name.toLowerCase().includes(lcTerm)
      })
    })
    const hasResults = newFilters.length > 0

    setHasFilterSearchResults(hasResults)
    setMatchingFilters(newFilters)
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
              <div className='filters-search-bar'>
                <div>
                  <FormControl
                    id={`filters-search-bar-${facet.id}`}
                    type='text'
                    autoComplete='false'
                    placeholder='Search for a filter'
                    value={searchText}
                    onChange={e => {
                      setSearchText(e.target.value)
                      searchFilters(e.target.value)
                    }
                  }
                  />
                  <div className="input-group-append">
                    <Button
                      className='search-button'
                      aria-label='Search'
                    >
                      <FontAwesomeIcon icon={faSearch}/>
                    </Button>
                  </div>
                </div>
              </div>
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
