import { useEffect } from 'react'
import { navigate, useLocation } from '@reach/router'
import * as queryString from 'query-string'

import { stringifyQuery, geneParamToArray, geneArrayToParam } from 'lib/scp-api'
import { getIdentifierForAnnotation } from 'lib/cluster-utils'
import { DEFAULT_ROW_CENTERING } from 'components/visualization/Heatmap'
import { startPendingEvent } from 'lib/metrics-api'
import { logStudyGeneSearch } from 'lib/scp-api-metrics'

export const emptyDataParams = {
  cluster: '',
  annotation: '',
  subsample: '',
  consensus: null
}

const SPATIAL_GROUPS_EMPTY = '--'
// because we only allow a single ExploreTabRouter component we can track global state here, instead
// of useRef, which would trigger a rerender
let isInitialLoad = true

/**
 * manages view options and basic layout for the explore tab
 * this component handles calling the api explore endpoint to get view options (clusters, etc..) for the study
 */
export default function useExploreTabRouter() {
  const routerLocation = useLocation()
  const exploreParams = buildExploreParamsFromQuery(routerLocation.search)

  if (isInitialLoad) {
    // Log how long it takes from starting page load until completing first plot
    startPendingEvent('user-action:page:view:site-study',
      { speciesList: window.SCP.taxons },
      'plot:',
      true)

    if (exploreParams.genes.length > 0) {
      // note that we can't pass the species list because we don't know it yet.
      logStudyGeneSearch(exploreParams.genes, 'url')
    }
  }
  isInitialLoad = false

  /** Merges the received update into the exploreParams, and updates the page URL if need */
  function updateExploreParams(newOptions, wasUserSpecified=true) {
    const mergedOpts = Object.assign({}, exploreParams, newOptions)
    if (wasUserSpecified) {
      // this is just default params being fetched from the server, so don't change the url
      Object.keys(newOptions).forEach(key => {
        mergedOpts.userSpecified[key] = true
      })
      if (newOptions.consensus || newOptions.genes) {
        // if the user does a gene search or changes the consensus, switch back to the default tab
        delete mergedOpts.tab
        delete mergedOpts.userSpecified.tab
      }
    }

    const query = buildQueryFromParams(mergedOpts)
    // view options settings should not add history entries
    // e.g. when a user hits 'back', it shouldn't undo their cluster selection,
    // it should take them to the page they were on before they came to the explore tab
    navigate(`${query}#study-visualize`, { replace: true })
  }

  useEffect(() => {
    // this cleanup isn't strictly necessary now, but if we ever start linking to gene searches
    // within SCP, or not reloading the page when going from search results to explore, it will be needed
    return function cleanup() {
      isInitialLoad = true
    }
  })
  return { exploreParams, updateExploreParams, routerLocation }
}

/** converts query string parameters into the dataParams objet */
function buildExploreParamsFromQuery(query) {
  const exploreParams = {
    userSpecified: {}
  }
  const queryParams = queryString.parse(query)
  let annotation = {
    name: '',
    scope: '',
    type: ''
  }
  if (queryParams.annotation) {
    const [name, type, scope] = queryParams.annotation.split('--')
    annotation = { name, type, scope }
    if (name && name.length > 0) {
      exploreParams.userSpecified.annotation = true
    }
  }

  PARAM_LIST_ORDER.forEach(param => {
    if (queryParams[param] && queryParams[param].length) {
      exploreParams.userSpecified[param] = true
    }
  })
  exploreParams.cluster = queryParams.cluster ? queryParams.cluster : ''
  exploreParams.annotation = annotation
  exploreParams.subsample = queryParams.subsample ? queryParams.subsample : ''
  exploreParams.consensus = queryParams.consensus ? queryParams.consensus : null
  if (queryParams.spatialGroups === SPATIAL_GROUPS_EMPTY) {
    exploreParams.spatialGroups = []
  } else {
    exploreParams.spatialGroups = queryParams.spatialGroups ? queryParams.spatialGroups.split(',') : []
  }
  exploreParams.genes = geneParamToArray(queryParams.genes)
  exploreParams.geneList = queryParams.geneList ? queryParams.geneList : ''
  exploreParams.heatmapRowCentering = queryParams.heatmapRowCentering ?
    queryParams.heatmapRowCentering :
    DEFAULT_ROW_CENTERING

  exploreParams.scatterColor = queryParams.scatterColor ? queryParams.scatterColor : ''
  exploreParams.distributionPlot = queryParams.distributionPlot ? queryParams.distributionPlot : ''
  exploreParams.distributionPoints = queryParams.distributionPoints ? queryParams.distributionPoints : ''
  exploreParams.tab = queryParams.tab ? queryParams.tab : ''
  exploreParams.heatmapFit = queryParams.heatmapFit ? queryParams.heatmapFit : ''
  exploreParams.bamFileName = queryParams.bamFileName ? queryParams.bamFileName : ''
  exploreParams.ideogramFileId = queryParams.ideogramFileId ? queryParams.ideogramFileId : ''


  return exploreParams
}

/** converts the params objects into a query string, inverse of build*ParamsFromQuery */
function buildQueryFromParams(exploreParams) {
  const querySafeOptions = {
    cluster: exploreParams.cluster,
    annotation: getIdentifierForAnnotation(exploreParams.annotation),
    subsample: exploreParams.subsample,
    genes: geneArrayToParam(exploreParams.genes),
    consensus: exploreParams.consensus,
    geneList: exploreParams.geneList,
    spatialGroups: exploreParams.spatialGroups.join(','),
    heatmapRowCentering: exploreParams.heatmapRowCentering,
    tab: exploreParams.tab,
    scatterColor: exploreParams.scatterColor,
    distributionPlot: exploreParams.distributionPlot,
    distributionPoints: exploreParams.distributionPoints,
    heatmapFit: exploreParams.heatmapFit,
    bamFileName: exploreParams.bamFileName,
    ideogramFileId: exploreParams.ideogramFileId
  }

  if (querySafeOptions.spatialGroups === '' && exploreParams.userSpecified['spatialGroups']) {
    querySafeOptions.spatialGroups = SPATIAL_GROUPS_EMPTY
  }
  // remove keys which were not user-specified
  Object.keys(querySafeOptions).forEach(key => {
    if (!exploreParams.userSpecified[key] && !exploreParams.userSpecified[key]) {
      delete querySafeOptions[key]
    }
  })

  return stringifyQuery(querySafeOptions, paramSorter)
}

/** controls list in which query string params are rendered into URL bar */
const PARAM_LIST_ORDER = ['geneList', 'genes', 'cluster', 'spatialGroups', 'annotation', 'subsample', 'consensus',
  'tab', 'scatterColor', 'distributionPlot', 'distributionPoints', 'heatmapFit', 'heatmapRowCentering', 'bamFileName', 'ideogramFileId']
/** sort function for passing to stringify to ensure url params are specified in a user-friendly order */
function paramSorter(a, b) {
  return PARAM_LIST_ORDER.indexOf(a) - PARAM_LIST_ORDER.indexOf(b)
}
