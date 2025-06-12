import React, { useState } from 'react'
import _cloneDeep from 'lodash/cloneDeep'
import _isEqual from 'lodash/isEqual'
import { navigate, useLocation } from '@reach/router'
import * as queryString from 'query-string'

import { fetchSearch, buildSearchQueryString, buildFacetsFromQueryString } from '~/lib/scp-api'
import { buildParamsFromQuery as buildStudyParamsFromQuery } from '~/providers/StudySearchProvider'

/*
 * This component and context shares a LOT in common with StudySearchProvider
 * Once we decide how Study and gene search interact in the UI, these two providers
 * should be refactored to consolidate search logic
 */

export const emptySearch = {
  params: {
    genes: '',
    terms: '',
    facets: {},
    genePage: 1
  },

  results: [],
  isLoading: false,
  isLoaded: false,
  isError: false,

  updateSearch: () => {
    throw new Error(
      'You are trying to use this context outside of a Provider container'
    )
  }
}

export const GeneSearchContext = React.createContext(emptySearch)

/**
  * renders a GeneSearchContext tied to its props,
  * fires route navigate on changes to params
  */
export function PropsGeneSearchProvider(props) {
  const defaultState = _cloneDeep(emptySearch)
  defaultState.updateSearch = updateSearch
  defaultState.performSearch = performSearch
  const [searchState, setSearchState] = useState(defaultState)
  const searchParams = props.searchParams


  /**
   * Update search parameters in URL
   *
   * @param {Object} newParams Parameters to update
   */
  async function updateSearch(newParams) {
    let mergedParams = Object.assign({}, searchParams, newParams)
    // reset the page to 1 for new searches, unless otherwise specified
    // we convert 'page' to 'genePage' so the url param
    // doesn't conflict with the study search page
    mergedParams.genePage = newParams.page ? newParams.page : 1
    // merge in the study params so that state is saved between tabs
    mergedParams = Object.assign(buildStudyParamsFromQuery(window.location.search), mergedParams)
    const queryString = buildSearchQueryString('study', mergedParams)
    navigate(`?${queryString}`)
  }

  /** perform the actual API search */
  function performSearch() {
    // reset the scroll in case they scrolled down to read prior results
    window.scrollTo(0, 0)

    fetchSearch(
      // Ensures event properties include "type": "gene" in search logging.
      'gene', {
        page: searchParams.page,
        genes: searchParams.genes,
        terms: searchParams.terms,
        facets: searchParams.facets,
        preset: searchParams.preset
      }).then(results => {
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

  if (!_isEqual(searchParams, searchState.params ||
      !searchState.isLoading &&
      !searchState.isLoaded)) {
    performSearch(searchParams)

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
    <GeneSearchContext.Provider value={searchState}>
      { props.children }
    </GeneSearchContext.Provider>
  )
}

/** returns an object built from the query params and defaults */
export function buildParamsFromQuery(query, preset) {
  const queryParams = queryString.parse(query)
  const cleanGeneParams = sanitizeGeneParams(queryParams)
  return {
    page: queryParams.genePage ? parseInt(queryParams.genePage) : 1,
    genes: cleanGeneParams,
    terms: queryParams.terms ? queryParams.terms : '',
    external: queryParams.external ? queryParams.external : '',
    facets: buildFacetsFromQueryString(queryParams.facets),
    preset: preset ? preset : queryString.preset_search
  }
}

/** strip any beginning or end quotes from a gene param */
function stripOffQuotes(geneParam) {
  const cleanedWord = geneParam.replace(/"\B/, '').replace(/\B"/, '').trim()
  return cleanedWord
}

/** sanitize gene params */
function sanitizeGeneParams(queryParams) {
  if (!queryParams.genes) {
    return ''
  } else {
    const geneParamArray = queryParams.genes.split(' ')
    const sanitizedGeneParams = geneParamArray.map(stripOffQuotes)
    return sanitizedGeneParams.join(' ')
  }
}

/**
 * Self-contained component for providing a url-routable
 * GeneSearchContext and rendering children.
 * The routing is all via query params
 */
export default function GeneSearchProvider({ children }) {
  const location = useLocation()
  const preset = location.pathname.includes('covid19') ? 'covid19' : ''
  const searchParams = buildParamsFromQuery(location.search, preset)
  return (
    <PropsGeneSearchProvider searchParams={searchParams}>
      {children}
    </PropsGeneSearchProvider>
  )
}
