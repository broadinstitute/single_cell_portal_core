/**
 * @fileoverview Functions for client-side usage analytics of SCP REST API
 */

import {
  getNumberOfTerms, getNumFacetsAndFilters
} from 'providers/StudySearchProvider'
import { log } from './metrics-api'

// See note in logSearch
let isPageLoadSearch = true

const filterNamesById = {}

/**
 * Populates global id-to-name map of retrieved filters, for easier analytics.
 * See downstream use of window.SCP.filterNamesById in metrics-api.js.
 */
export function mapFiltersForLogging(facetsOrFilters, isFacets=false) {
  // If testing, skip.  Tech debt to reconsider later.
  if ('SCP' in window === false) return

  // This construct is kludgy, but helps cohesion and encapsulation
  // by putting related dense code here instead of in the calling functions
  if (isFacets) {
    const facets = facetsOrFilters
    facets.map(facet => {
      facet.filters.map(filter => {
        filterNamesById[filter.id] = filter.name
      })
    })
  } else {
    let filters = facetsOrFilters
    // handle facet filter search results
    if (facetsOrFilters.filters) {
      filters = facetsOrFilters.filters
    }
    filters.map(filter => {
      filterNamesById[filter.id] = filter.name
    })
  }
}

/**
 * Returns human-friendly list of applied filters for each facet
 *
 * This enables us to more feasibly answer "What filters are people using?"
 *
 * Renames keys in facets for easier discoverability as event properties in
 * Mixpanel.  E.g. instead of "disease" and "species", which will not appear
 * together in Mixpanel's alphabetized list, log these as "filtersDisease" and
 * "filtersSpecies".
 *
 * Also renames filters from opaque IDs (e.g. MONDO_0018076) to human-readable
 * labels (e.g. tuberculosis).
 */
function getFriendlyFilterListByFacet(facets) {
  const filterListByFacet = {}
  if (!facets) {
    return filterListByFacet
  }
  Object.entries(facets).forEach(([facet, filters]) => {
    const friendlyFacet = `filters${facet[0].toUpperCase() + facet.slice(1)}`
    const friendlyFilters = filters.map(filterId => {
      // This global variable is initialized in application.html.erb
      // and populated in scp-api.js
      return filterNamesById[filterId]
    })
    filterListByFacet[friendlyFacet] = friendlyFilters
  })
  return filterListByFacet
}

/**
 * Log study search metrics.  Might support gene, cell search in future.
 */
export function logSearch(type, searchParams) {
  if (isPageLoadSearch === true) {
    // This prevents over-reporting searches.
    // Loading home page triggers search, which is a side-effect / artifact
    // with regard to tracking user interactions.  This variable is set to
    // false once per page load as a way to omit such artifacts from logging.
    isPageLoadSearch = false
    return
  }

  const terms = searchParams.terms ? searchParams.terms.split(' ') : ''
  const facets = searchParams.facets
  const page = searchParams.page
  const genes = searchParams.genes
  const preset = searchParams.preset

  const numTerms = getNumberOfTerms(terms)
  const [numFacets, numFilters] = getNumFacetsAndFilters(facets)
  const facetList = facets ? Object.keys(facets) : []

  const filterListByFacet = getFriendlyFilterListByFacet(facets)

  const simpleProps = {
    type, terms, page, preset,
    numTerms, numFacets, numFilters, facetList, genes,
    context: 'global'
  }
  const props = Object.assign(simpleProps, filterListByFacet)

  log('search', props)

  let gaEventCategory = 'advanced-search'
  // e.g. advanced-search-covid19
  if (
    preset !== '' &&
    typeof preset !== 'undefined'
  ) {
    gaEventCategory += `-${preset}`
  }

  // Google Analytics fallback: remove once Bard and Mixpanel are ready for SCP
  ga( // eslint-disable-line no-undef
    'send', 'event', gaEventCategory, 'study-search',
    'num-terms', numTerms
  )
}

/**
 * Log filter search metrics
 */
export function logFilterSearch(facet, terms) {
  const numTerms = getNumberOfTerms(terms)

  const defaultProps = { facet, terms }
  const props = Object.assign(defaultProps, { numTerms })
  log('search-filter', props)

  // Google Analytics fallback: remove once Bard and Mixpanel are ready for SCP
  ga( // eslint-disable-line no-undef
    'send', 'event', 'advanced-search', 'search-filter',
    'num-terms', numTerms
  )
}

/**
 * Log when a download is authorized.
 * This is our best web-client-side methodology for measuring downloads.
 */
export function logDownloadAuthorization() {
  log('download-authorization')
  ga('send', 'event', 'advanced-search', 'download-authorization') // eslint-disable-line no-undef, max-len
}
