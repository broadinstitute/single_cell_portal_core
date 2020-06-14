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
export default function FiltersBoxSearchable({ facet, selection, setSelection, show, setShow, hideApply }) {
  // State that is specific to FiltersBox
  const [matchingFilters, setMatchingFilters] = useState(facet.filters.slice(0, 15))
  const [hasFilterSearchResults, setHasFilterSearchResults] = useState(false)

  /*
   * TODO: Get opinions, perhaps move to a UI code style guide.
   *
   * Systematic, predictable IDs help UX research and UI development.
   *
   * Form of IDs: <general name> <specific name(s)>
   * General: All lowercase, specified in app code (e.g. 'apply-facet')
   * Specific: Cased as specified in API (e.g. 'species', 'NCBItaxon9606')
   * /single_cell/studies/5e9e07bd771a5b2caa140971/upload
   * UI code concatenates names in the ID.  Names in ID are hyphen-delimited.

https://singlecell.broadinstitute.org/single_cell/study/SCP279/amp-phase-1/gene_expression/foxp3
?annotation=Cluster--group--study
&boxpoints=all
&cluster=t-SNE%20coordinates%20RA&colorscale=Reds&
consensus=&heatmap_row_centering=z-score&heatmap_size=NaN&plot_type=violin&subsample=1000


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
    let filtersSummary = 'Top Filters'

    if (hasFilterSearchResults) {
      const numMatches = matchingFilters.length
      const resultsName = pluralize(facetName, numMatches)
      filtersSummary = `${numMatches} ${resultsName} found`
    }
    return filtersSummary
  }

  function removeFilter(filterId) {
    const newSelections = selection.slice()
    _remove(newSelections, id => {return id === filterId})
    setSelection(newSelections)
  }

  const showSearchBar = facet.links.length > 0 || facet.filters.length > 10
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
                          href={link.url}
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
            hideApply={hideApply}
          />
        </div>
      }
    </>
  )
}
