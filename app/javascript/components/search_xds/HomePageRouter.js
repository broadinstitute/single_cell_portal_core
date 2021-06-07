import { useEffect } from 'react'
import { navigate, useLocation } from '@reach/router'
import * as queryString from 'query-string'

import { stringifyQuery } from 'lib/scp-api'
// import { logGlobalGeneSearch } from 'lib/metrics-api'

/**
 * manages view options and basic layout for the home page
 * this component handles calling the API explore endpoint to get view options (clusters, etc..) for the study
 */
export default function useHomePageRouter() {
  const routerLocation = useLocation()
  const homeParams = buildHomeParamsFromQuery(routerLocation.search)

  console.log(routerLocation.search)
  console.log('homeParams -1', homeParams)

  /** reset to the default view for a study */
  function clearHomeParams() {
    navigate('')
  }

  useEffect(() => {
    // if this is the first render, and there are already genes specified, that means they came
    // from the URL directly
    if (homeParams.genes.length > 0) {
      // logGlobalGeneSearch(homeParams.genes, 'url')
    }
  }, [])
  return { homeParams, updateHomeParams, routerLocation, clearHomeParams }
}

/** Merges the received update into the homeParams, and updates the page URL if need */
function updateHomeParams(newOptions, wasUserSpecified=true) {
  // rebuild the params from the actual URL to avoid races
  const search = location.search
  const currentParams = buildHomeParamsFromQuery(search)
  const mergedOpts = Object.assign({}, currentParams, newOptions)
  if (wasUserSpecified) {
    // this is just default params being fetched from the server, so don't change the URL
    Object.keys(newOptions).forEach(key => {
      mergedOpts.userSpecified[key] = true
    })
  }

  const query = buildQueryFromParams(mergedOpts)
  // view options settings should not add history entries
  // e.g. when a user hits 'back', it shouldn't undo their cluster selection,
  // it should take them to the page they were on before they came to the home page
  navigate(query, { replace: true })
}

/** converts query string parameters into the dataParams object */
function buildHomeParamsFromQuery(query) {
  const homeParams = {
    userSpecified: {}
  }
  const queryParams = queryString.parse(query)

  const preset = location.pathname.includes('covid19') ? 'covid19' : ''

  PARAM_LIST_ORDER.forEach(param => {
    if (queryParams[param] && queryParams[param].length) {
      homeParams.userSpecified[param] = true
    }
  })
  homeParams.terms = queryParams.terms ? queryParams.terms : '',
  homeParams.genes = queryParams.genes ? queryParams.genes : [],
  homeParams.facets = buildFacetsFromQueryString(queryParams.facets),
  homeParams.type = queryParams.type ? queryParams.type : '',
  homeParams.page = queryParams.page ? parseInt(queryParams.page) : 1,
  homeParams.preset = preset ? preset : queryString.preset_search,
  homeParams.order = queryParams.order

  return homeParams
}

/** Deserializes "facets" URL parameter into facets object */
function buildFacetsFromQueryString(facetsParamString) {
  const facets = {}
  if (facetsParamString) {
    facetsParamString.split('+').forEach(facetString => {
      const facetArray = facetString.split(':')
      facets[facetArray[0]] = facetArray[1].split(',')
    })
  }
  return facets
}

/** converts the params objects into a query string, inverse of build*ParamsFromQuery */
function buildQueryFromParams(homeParams) {
  const querySafeOptions = {
    terms: homeParams.terms,
    genes: homeParams.genes,
    facets: homeParams.facets,
    type: homeParams.type,
    page: homeParams.page,
    preset: homeParams.preset,
    order: homeParams.order
  }

  // remove keys which were not user-specified
  Object.keys(querySafeOptions).forEach(key => {
    if (!homeParams.userSpecified[key] && !homeParams.userSpecified[key]) {
      delete querySafeOptions[key]
    }
  })

  return stringifyQuery(querySafeOptions, paramSorter)
}

/** controls list in which query string params are rendered into URL bar */
const PARAM_LIST_ORDER = ['terms', 'genes', 'facets', 'type', 'page', 'order']
/** sort function for passing to stringify to ensure url params are specified in a user-friendly order */
function paramSorter(a, b) {
  return PARAM_LIST_ORDER.indexOf(a) - PARAM_LIST_ORDER.indexOf(b)
}
