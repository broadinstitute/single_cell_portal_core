import React, { useContext, useState } from 'react'
import _cloneDeep from 'lodash/cloneDeep'
import _isEqual from 'lodash/isEqual'
import { navigate, useLocation } from '@reach/router'
import * as queryString from 'query-string'

import {
  fetchSearch,
  buildSearchQueryString,
  buildFacetsFromQueryString
} from '~/lib/scp-api'
import SearchSelectionProvider from './SearchSelectionProvider'
import { buildParamsFromQuery as buildGeneParamsFromQuery } from './GeneSearchProvider'


const emptySearch = {
  params: {
    terms: '',
    facets: {},
    page: 1,
    preset_search: undefined,
    order: undefined
  },

  results: [],
  isLoading: false,
  isLoaded: false,
  isError: false,

  updateSearch: () => {
    throw new Error(
      'You are trying to use this context outside of a Provider container'
    )
  },
  performSearch: () => {
    throw new Error(
      'You are trying to use this context outside of a Provider container'
    )
  }
}

export const StudySearchContext = React.createContext(emptySearch)


/**
 * Counts facets (e.g. species, disease) and filters (e.g. human, COVID-19)
 */
export function getNumFacetsAndFilters(facets) {
  if (!facets) {
    return [0, 0]
  }
  const numFacets = Object.keys(facets).length
  const numFilters = Object.values(facets).reduce(
    (prevNumFilters, filterArray) => {
      return prevNumFilters + filterArray.length
    },
    0
  )

  return [numFacets, numFilters]
}

/** returns the applied (i.e. sent to server for search) params for the given facet object */
export function getAppliedParamsForFacet(facet, searchContext) {
  let appliedParams = []
  if (searchContext.params.facets[facet.id]) {
    appliedParams = searchContext.params.facets[facet.id]
  }
  return appliedParams
}

/** Wrapper for deep mocking via Jest / Enzyme */
export function useContextStudySearch() {
  return useContext(StudySearchContext)
}

/**
 * renders a StudySearchContext tied to its props,
 * fires route navigate on changes to params
 */
export function PropsStudySearchProvider(props) {
  const startingState = _cloneDeep(emptySearch)
  startingState.params = props.searchParams
  // attach the perform and update methods to the context to avoid prop-drilling
  startingState.performSearch = performSearch
  startingState.updateSearch = updateSearch
  const [searchState, setSearchState] = useState(startingState)
  const searchParams = props.searchParams

  /**
   * Update search parameters in URL
   * @param {Object} newParams Parameters to update
   */
  async function updateSearch(newParams) {
    const search = Object.assign({}, searchParams, newParams)
    search.facets = Object.assign({}, searchParams.facets, newParams.facets)
    // reset the page to 1 for new searches, unless otherwise specified
    search.page = newParams.page ? newParams.page : 1
    search.preset = undefined // for now, exclude preset from the page URL--it's in the component props instead
    const mergedParams = Object.assign(buildGeneParamsFromQuery(window.location.search), search)
    const queryString = buildSearchQueryString('study', mergedParams)
    navigate(`?${queryString}`)
  }

  /** perform the actual API search based on current params */
  function performSearch() {
    // reset the scroll in case they scrolled down to read prior results
    window.scrollTo(0, 0)

    fetchSearch('study', searchParams).then(results => {
      setSearchState({
        params: searchParams,
        isError: false,
        isLoading: false,
        isLoaded: true,
        results,
        updateSearch
      })
    }).catch(error => {
      setSearchState({
        params: searchParams,
        isError: true,
        isLoading: false,
        isLoaded: true,
        results: error,
        updateSearch
      })
    })
  }

  if (!_isEqual(searchParams, searchState.params)) {
    performSearch()
    setSearchState({
      params: searchParams,
      isError: false,
      isLoading: true,
      isLoaded: false,
      results: [],
      updateSearch
    })
  }
  return (
    <StudySearchContext.Provider value={searchState}>
      <SearchSelectionProvider>{props.children}</SearchSelectionProvider>
    </StudySearchContext.Provider>
  )
}

/** returns an object with the query params and defaults applied */
export function buildParamsFromQuery(query, preset) {
  const queryParams = queryString.parse(query)
  return {
    page: queryParams.page ? parseInt(queryParams.page) : 1,
    terms: queryParams.terms ? queryParams.terms : '',
    facets: buildFacetsFromQueryString(queryParams.facets),
    external: queryParams.external ? queryParams.external : '',
    preset: preset ? preset : queryString.preset_search,
    order: queryParams.order
  }
}

/**
 * Self-contained component for providing a url-routable
 * StudySearchContext and rendering children.
 * The routing is all via query params
 */
export default function StudySearchProvider({ children }) {
  const location = useLocation()
  const preset = location.pathname.includes('covid19') ? 'covid19' : ''
  const searchParams = buildParamsFromQuery(location.search, preset)
  return (
    <PropsStudySearchProvider searchParams={searchParams}>
      {children}
    </PropsStudySearchProvider>
  )
}
