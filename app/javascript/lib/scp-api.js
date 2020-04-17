/**
 * @fileoverview JavaScript client for Single Cell Portal REST API
 *
 * Succinct, well-documented SCP API wrappers, also enabling easy mocks
 *
 * API docs: https://singlecell.broadinstitute.org/single_cell/api
 */

import camelcaseKeys from 'camelcase-keys'
import _compact from 'lodash/compact'
import * as queryString from 'query-string'

import { accessToken } from 'providers/UserProvider'
import {
  logFilterSearch,
  logSearch,
  logDownloadAuthorization,
  mapFiltersForLogging
} from './scp-api-metrics'

// If true, returns mock data for all API responses.  Only for dev.
let globalMock = false

const defaultBasePath = '/single_cell/api/v1'

function defaultInit() {
  const headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json'
  }
  // accessToken is a blank string when not signed in
  if (accessToken !== '') {
    headers['Authorization'] = `Bearer ${accessToken}`
  }
  return {
    method: 'GET',
    headers
  }
}

<<<<<<< HEAD
if (
  accessToken !== '' // accessToken is a blank string when not signed in
) {
  defaultInit.headers = Object.assign(defaultInit.headers, {
    Authorization: `Bearer ${accessToken}`
  })
}
=======
>>>>>>> 6f65eab85d3814138cb768a18bfaf2880dbefc64

/**
 * Get a one-time authorization code for download, and its lifetime in seconds
 *
 * TODO:
 * - Update API to use "expires_in" instead of "time_interval"
 *
 * Docs: https:///singlecell.broadinstitute.org/single_cell/api/swagger_docs/v1#!/Search/search_auth_code_path
 *
 * @param {Boolean} mock Whether to use mock data.  Helps development, tests.
 * @returns {Promise} Promise object described in "Example return" above
 *
 * @example
 *
 * // returns {authCode: 123456, timeInterval: 1800}
 * fetchAuthCode(true)
 */
export async function fetchAuthCode(mock = false) {
  let init = defaultInit
  if (mock === false && globalMock === false) {
    init = Object.assign({}, defaultInit(), {
      method: 'POST'
    })
  }
  logDownloadAuthorization()
  return await scpApi('/search/auth_code', init, mock)
}

/**
 * Returns list of all available search facets, including default filter values
 *
 * Docs: https:///singlecell.broadinstitute.org/single_cell/api/swagger_docs/v1#!/Search/search_facets_path
 *
 * @param {Boolean} mock Whether to use mock data.  Helps development, tests.
 * @returns {Promise} Promise object containing camel-cased data from API
 */
<<<<<<< HEAD
export async function fetchFacets(mock = false) {
  const facets = await scpApi('/search/facets', defaultInit, mock)
=======
export async function fetchFacets(mock=false) {
  const facets = await scpApi('/search/facets', defaultInit(), mock)
>>>>>>> 6f65eab85d3814138cb768a18bfaf2880dbefc64

  mapFiltersForLogging(facets, true)

  return facets
}

/**
 * Sets flag on whether to use mock data for all API responses.
 *
 * This method is useful for tests and certain development scenarios,
 * e.g. when evolving a new API or to work around occasional API blockers.
 *
 * @param {Boolean} flag Whether to use mock data for all API responses
 */
export function setGlobalMockFlag(flag) {
  globalMock = flag
}

// Modifiable in setMockOrigin, used in unit tests
let mockOrigin = ''

/**
 * Sets origin (e.g. http://localhost:3000) for mocked SCP API URLs
 *
 * This enables mock data to be used from Jest tests
 *
 * @param {Boolean} origin Origin (e.g. http://localhost:3000) for mocked SCP API URLs
 */
export function setMockOrigin(origin) {
  mockOrigin = origin
}

/**
 *  Returns an object with violin plot expression data rendering info for a single gene on a single study
 *
 * @param {string} studyAccession study
 * @param {Array} genes List of gene names or identifiers to get expression data for
 *
 */
export async function fetchExpressionViolin(studyAccession, gene, cluster, annotation, subsample, mock=false) {
  const clusterParam = cluster ? `&cluster=${encodeURIComponent(cluster)}` : ''
  const annotationParam = annotation ? `&annotation=${encodeURIComponent(annotation)}` : ''
  const subsampleParam = subsample ? `&subsample=${encodeURIComponent(subsample)}` : ''
  const apiUrl = `/studies/${studyAccession}/expression_data/violin?gene=${gene}${clusterParam}${annotationParam}${subsampleParam}`
  // don't camelcase the keys since those can be cluster names, so send false for the 4th argument
  return await scpApi(apiUrl, defaultInit(), mock, false)
}

export async function fetchAnnotationValues(studyAccession, mock=false) {
  const apiUrl = `/studies/${studyAccession}/expression_data/annotations`
  return await scpApi(apiUrl, defaultInit(), mock, false)
}

/**
 *  Returns an object with violin plot expression data rendering info for a single gene on a single study
 *
 * @param {string} studyAccession study
 * @param {Array} genes List of gene names or identifiers to get expression data for
 *
 */
export async function fetchExpressionHeatmap(studyAccession, genes, cluster, annotation, subsample, mock=false) {
  const clusterParam = cluster ? `&cluster=${encodeURIComponent(cluster)}` : ''
  const annotationParam = annotation ? `&annotation=${encodeURIComponent(annotation)}` : ''
  const subsampleParam = subsample ? `&annotation=${encodeURIComponent(subsample)}` : ''
  const genesParam = encodeURIComponent(genes.join(','))
  const apiUrl = `/studies/${studyAccession}/expression_heatmaps?genes=${genesParam}${clusterParam}${annotationParam}${subsampleParam}`
  // don't camelcase the keys since those can be cluster names, so send false for the 4th argument
  return await scpApi(apiUrl, defaultInit(), mock, false)
}

export function studyNameAsUrlParam(studyName) {
  return studyName.toLowerCase().replace(/ /g, '-').replace(/[^0-9a-z-]/gi, '')
}

/**
 * Returns a list of matching filters for a given facet
 *
 * Docs: https:///singlecell.broadinstitute.org/single_cell/api/swagger_docs/v1#!/Search/search_facet_filters_path
 *
 * @param {String} facet Identifier of facet
 * @param {String} query User-supplied query string
 * @param {Boolean} mock Whether to use mock data.  Helps development, tests.
 * @returns {Promise} Promise object containing camel-cased data from API
 *
 * @example
 *
 * // returns Promise for mock JSON
 * // in /mock_data/facet_filters_disease_tuberculosis.json
 * fetchFacetFilters('disease', 'tuberculosis', true);
 *
 * // returns Promise for live JSON as shown example from
 * // "Docs" link above (but camel-cased)
 * fetchFacetFilters('disease', 'tuberculosis');
 */
export async function fetchFacetFilters(facet, query, mock = false) {
  let queryString = `?facet=${facet}&query=${query}`
  if (mock || globalMock) {
    queryString = `_${facet}_${query}`
  }

  logFilterSearch(facet, query)

  const pathAndQueryString = `/search/facet_filters${queryString}`

  const filters = await scpApi(pathAndQueryString, defaultInit(), mock)

  mapFiltersForLogging(filters)

  return filters
}

/**
 *  Returns number of files and bytes (by file type), to preview bulk download
 *
 * Docs:
 * https://singlecell.broadinstitute.org/single_cell/api/swagger_docs/v1#!/Search/search_bulk_download_size_path
 *
 * @param {Array} List of study accessions to preview download
 * @param {Array} fileTypes List of file types in studies to preview download
 *
 * @example returns Promise for JSON
 * {"Expression":{"total_files":4,"total_bytes":1797720765},"Metadata":{"total_files":2,"total_bytes":865371}}
 * fetchDownloadSize([SCP200, SCP201], ["Expression", "Metadata"])
 */
export async function fetchDownloadSize(accessions, fileTypes, mock = false) {
  const fileTypesString = fileTypes.join(',')
  const queryString = `?accessions=${accessions}&file_types=${fileTypesString}`
  const pathAndQueryString = `/search/bulk_download_size/${queryString}`
  return await scpApi(pathAndQueryString, defaultInit(), mock)
}

/**
 * Returns a list of matching studies given a keyword and facets
 *
 * Docs: https:///singlecell.broadinstitute.org/single_cell/api/swagger_docs/v1#!/Search/search_facet_filters_path
 *
 * @param {String} type Type of query to perform (study- or cell-based)
 * @param {Object} searchParams  User-supplied search parameters including
 * @param {String} terms: User-supplied query string
 * @param {Object} facets: User-supplied list facets and filters
 * @param{Integer} page: User-supplied list facets and filters
 * @param {String} order: User-supplied results ordering field
 * @param {String} preset_search: User-supplied query preset (e.g. 'covid19')
 * @param {Boolean} mock Whether to use mock data
 * @returns {Promise} Promise object containing camel-cased data from API
 *
 * @example
 *
 * fetchSearch('study', 'tuberculosis');
 */
export async function fetchSearch(type, searchParams, mock = false) {
  const path = `/search?${buildSearchQueryString(type, searchParams)}`

  const searchResults = await scpApi(path, defaultInit(), mock)

  logSearch(type, searchParams)

  return searchResults
}

/**
 * Constructs query string used for /search REST API endpoint
 * auto-appends the branding group if one exists
 */
export function buildSearchQueryString(type, searchParams) {
  const facetsParam = buildFacetQueryString(searchParams.facets)

  let otherParamString = ['page', 'order', 'terms', 'preset', 'genes', 'genePage'].map(param => {
    return searchParams[param] ? `&${param}=${searchParams[param]}` : ''
  }).join('')
  otherParamString = otherParamString.replace('preset=', 'preset_search=')

  let brandingGroupParam = ''
  const brandingGroup = getBrandingGroup()
  if (brandingGroup) {
    brandingGroupParam = `&scpbr=${brandingGroup}`
  }

  return `type=${type}${otherParamString}${facetsParam}${brandingGroupParam}`
}

/** Serializes "facets" URL parameter for /search API endpoint */
function buildFacetQueryString(facets) {
  if (!facets || !Object.keys(facets).length) {
    return ''
  }
  const rawURL = _compact(
    Object.keys(facets).map(facetId => {
      if (facets[facetId].length) {
        return `${facetId}:${facets[facetId].join(',')}`
      }
    })
  ).join('+')
  // encodeURIComponent needed for the + , : characters
  return `&facets=${encodeURIComponent(rawURL)}`
}

/** Deserializes "facets" URL parameter into facets object */
export function buildFacetsFromQueryString(facetsParamString) {
  const facets = {}
  if (facetsParamString) {
    facetsParamString.split('+').forEach(facetString => {
      const facetArray = facetString.split(':')
      facets[facetArray[0]] = facetArray[1].split(',')
    })
  }
  return facets
}

/** returns the current branding group as specified by the url  */
function getBrandingGroup(path) {
  const queryParams = queryString.parse(window.location.search)
  return queryParams.scpbr
}

/**
 * Client for SCP REST API.  Less fetch boilerplate, easier mocks.
 *
 * @param {String} path | Relative path for API endpoint, e.g. /search/auth_code
 * @param {Object} init | Object for settings, just like standard fetch `init`
 * @param {Boolean} mock | Whether to use mock data.  Helps development, tests.
 */
<<<<<<< HEAD
export default async function scpApi(path, init, mock = false) {
=======
export default async function scpApi(path, init, mock=false, camelCase=true, toJson=true) {
>>>>>>> 6f65eab85d3814138cb768a18bfaf2880dbefc64
  if (globalMock) mock = true
  console.log(mockOrigin)
  const basePath =
    mock || globalMock ? `${mockOrigin}/mock_data` : defaultBasePath
  let fullPath = basePath + path
  if (mock) fullPath += '.json' // e.g. /mock_data/search/auth_code.json

  const response = await fetch(fullPath, init)
    .catch(error => error)

  if (response.ok) {
    if (toJson) {
      const json = await response.json()
      // Converts API's snake_case to JS-preferrable camelCase,
      // for easy destructuring assignment.
      if (camelCase) {
        return camelcaseKeys(json)
      } else {
        return json
      }
    } else {
      return response
    }
  }
  return response
}
