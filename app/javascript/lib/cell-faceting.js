/**
 * @fileoverview Library to enable fast client-side filtering of plotted cells
 *
 * Explainer: https://github.com/broadinstitute/single_cell_portal_core/pull/1862
 */

import crossfilter from 'crossfilter2'

import {
  getGroupAnnotationsForClusterAndStudy, getIdentifierForAnnotation
} from '~/lib/cluster-utils'
import { fetchAnnotationFacets } from '~/lib/scp-api'
import { log } from '~/lib/metrics-api'


const CELL_TYPE_REGEX = new RegExp(/cell.*type/i)

// Detect if a string mentions disease, sickness, malignant or malignancy,
// indication, a frequent suffix of disease names, or a common suffix of cancer names
const DISEASE_REGEX = new RegExp(/(disease|disease|medical|sick|malignan|syndrom|indicat|itis|isis|osis|oma)/i)

/**
 * Prioritize unselected annotations to those worth showing by default as facets
 *
 * To start, show <= 5 annotations facets by default.
 *
 * Don't show current annotation as facet, as that's our "Color by", and
 * filterable in each visualization.
 *
 * Preconditions -- annotations must be:
 *   - Group-based and have > 1 group
 *   - Cluster-based _and for this cluster_ or study-wide
 *
 * Annotation prioritization logic applied here, after above preconditions are met:
 *
 *   0. Not currently selected -- this is set upstream, not here
 *   1. Conventional annotations for cell type or disease
 *   2. Non-conventional annotations for cell type or disease
 *   3. Other conventional annotations
 *   4. Cluster-based annotations
 *   5. Study-wide annotations
 *
 * Annotations in above categories often don't exist, in which case we fall to the
 * the next prioritization rule.
 */
function sortAnnotationsByRelevance(annotList) {
  let annotsToFacet = []

  /** Assess if annotation is already in annotsToFacet list */
  function isUnique(annot) {
    return !annotsToFacet.includes(annot)
  }

  const cellTypeAndDiseaseConventionalAnnots = annotList.filter(
    annot => ['cell_type__ontology_label', 'disease__ontology_label'].includes(annot.name)
  )
  annotsToFacet = annotsToFacet.concat(cellTypeAndDiseaseConventionalAnnots)

  const cellTypeOrClinicalAnnots = annotList.filter(
    annot => (CELL_TYPE_REGEX.test(annot.name) || DISEASE_REGEX.test(annot.name)) && isUnique(annot)
  )
  annotsToFacet = annotsToFacet.concat(cellTypeOrClinicalAnnots)

  const otherConventionalOntologyAnnots = annotList.filter(annot => {
    return annot.name.endsWith('__ontology_label') && isUnique(annot)
  })
  annotsToFacet = annotsToFacet.concat(otherConventionalOntologyAnnots)

  const otherConventionalIdAnnots = annotList.filter(
    annot => ['donor_id', 'biosample_id'].includes(annot.name) && isUnique(annot)
  )
  annotsToFacet = annotsToFacet.concat(otherConventionalIdAnnots)

  const clusterAnnots = annotList.filter(
    annot => ('cluster_name' in annot) && isUnique(annot)
  )
  annotsToFacet = annotsToFacet.concat(clusterAnnots)

  const studyAnnots = annotList.filter(
    annot => !('cluster_name' in annot) && isUnique(annot)
  )
  annotsToFacet = annotsToFacet.concat(studyAnnots)

  return annotsToFacet
}

/** Log metrics for filterCells to Mixpanel */
function logFilterCells(t0Counts, t0, filterableCells, results, selection) {
  const t1Counts = Date.now()
  const perfTimeCounts = t1Counts - t0Counts

  const t1 = Date.now()
  // Assemble analytics
  const filterPerfTime = t1 - t0
  const numCellsBefore = filterableCells.length
  const numCellsAfter = results.length
  const numFacetsSelected = Object.keys(selection).length
  const numFiltersSelected = Object.values(selection).reduce((numFilters, selectedFiltersForThisFacet) => {
    // return accumulator (an integer) + current value (an array, specifically its length)
    return numFilters + selectedFiltersForThisFacet.length
  }, 0)
  const filterLogProps = {
    'perfTime': filterPerfTime,
    'perfTime:counts': perfTimeCounts,
    numCellsBefore,
    numCellsAfter,
    numFacetsSelected,
    numFiltersSelected
  }

  // Log to Mixpanel
  log('filter-cells', filterLogProps)
}

/** Get filtered cell results */
export function filterCells(
  selection, cellsByFacet, initFacets, filtersByFacet, filterableCells
) {
  const t0 = Date.now()
  const facets =
  initFacets
    .filter(facet => facet.isLoaded)
    .map(facet => facet.annotation)

  let fn; let facet; let results

  if (Object.keys(selection).length === 0) {
    results = filterableCells
  } else {
    for (let i = 0; i < facets.length; i++) {
      facet = facets[i]
      if (facet in selection) { // e.g. 'infant_sick_YN'
        const friendlyFilters = selection[facet] // e.g. ['yes', 'NA']

        const filter = new Set()
        friendlyFilters.forEach(friendlyFilter => {
          const filterIndex = filtersByFacet[facet].indexOf(friendlyFilter)
          filter.add(filterIndex)
        })

        fn = function(d) {
          return filter.has(d)
        }

        // Apply the actual crossfilter method
        cellsByFacet[facet].filterFunction(fn)
      } else {
        fn = null
        // Apply the actual crossfilter method
        cellsByFacet[facet].filter(fn)
      }
    }
    results = cellsByFacet[facet].top(Infinity)
  }

  const annotationFacets = initFacets.map(facet => facet.annotation)
  const t0Counts = Date.now()
  const counts = getFilterCounts(annotationFacets, cellsByFacet, initFacets, selection)

  logFilterCells(t0Counts, t0, filterableCells, results, selection)

  return [results, counts]
}

/** Merge /facets responses from new and all prior batches */
function mergeFacetsResponses(newRawFacets, prevCellFaceting) {
  if (!prevCellFaceting) {
    return newRawFacets
  }

  const prevRawFacets = prevCellFaceting.rawFacets

  const facets = prevRawFacets.facets.concat(newRawFacets.facets)

  const cells = []
  for (let i = 0; i < prevRawFacets.cells.length; i++) {
    cells.push(prevRawFacets.cells[i].concat(newRawFacets.cells[i]))
  }

  const mergedRawFacets = { cells, facets }
  return mergedRawFacets
}

/** Omit any filters that match 0 cells in the current clustering */
function trimNullFilters(cellFaceting) {
  const filterCountsByFacet = cellFaceting.filterCounts
  const annotationFacets = cellFaceting.facets.map(facet => facet.annotation)
  const nonzeroFiltersByFacet = {} // filters to remove, as they match no cells
  const nonzeroFilterCountsByFacet = {}

  let hasAnyNullFilters = false

  const filterableCells = cellFaceting.filterableCells

  for (let i = 0; i < annotationFacets.length; i++) {
    const facet = annotationFacets[i]
    let facetHasNullFilter = false
    let nullFilterIndex

    const countsByFilter = filterCountsByFacet[facet]
    const nonzeroFilters = []
    const nonzeroFilterCounts = {}
    if (!countsByFilter) {
      continue
    }

    Object.entries(countsByFilter).forEach(([filter, count], filterIndex) => {
      if (count !== null) {
        nonzeroFilters.push(filter)
        nonzeroFilterCounts[filter] = countsByFilter[filter]
      } else {
        facetHasNullFilter = true

        hasAnyNullFilters = true
        nullFilterIndex = filterIndex
      }
    })

    if (facetHasNullFilter) {
      for (let j = 0; j < cellFaceting.filterableCells.length; j++) {
        const cell = cellFaceting.filterableCells[j]
        if (cell[i] > nullFilterIndex) {
          filterableCells[j][i] -= 1 // Shift facet filter index to account for removal
        }
      }
    }

    nonzeroFilterCountsByFacet[facet] = nonzeroFilterCounts
    nonzeroFiltersByFacet[facet] = nonzeroFilters
    cellFaceting.facets[i].groups = nonzeroFilters
  }

  if (!hasAnyNullFilters) {return cellFaceting}

  cellFaceting.cellsByFacet = getCellsByFacet(filterableCells, annotationFacets)
  cellFaceting.filterableCells = filterableCells
  cellFaceting.filterCounts = nonzeroFilterCountsByFacet
  cellFaceting.filtersByFacet = nonzeroFiltersByFacet

  return cellFaceting
}

/** Get counts for each filter, in each facet */
function getFilterCounts(annotationFacets, cellsByFacet, facets, selection) {
  const filterCounts = {}

  for (let i = 0; i < annotationFacets.length; i++) {
    const facet = annotationFacets[i]
    const facetCrossfilter = cellsByFacet[facet]
    // Set counts for each filter in facet
    const rawFilterCounts = facetCrossfilter.group().top(Infinity)
    const countsByFilter = {}

    facets[i].groups.forEach((group, j) => {
      let count = null
      const rawFilterKeyAndValue = rawFilterCounts.find(rfc => rfc.key === j)
      if (rawFilterKeyAndValue) {
        count = rawFilterKeyAndValue.value
      }
      countsByFilter[group] = count
    })
    filterCounts[facet] = countsByFilter
  }

  // If a filter has been deselected, set its count to 0
  if (selection) {
    Object.entries(filterCounts).forEach(([facet, countsByFilter]) => {
      Object.entries(countsByFilter).forEach(([filter, count]) => {
        let newCount = count
        if (!(facet in selection && selection[facet].includes(filter))) {
          newCount = 0
        }
        filterCounts[facet][filter] = newCount
      })
    })
  }

  return filterCounts
}

/** Get crossfilter-initialized cells by facet */
function getCellsByFacet(filterableCells, annotationFacets) {
  const cellCrossfilter = crossfilter(filterableCells)
  const cellsByFacet = {}
  for (let i = 0; i < annotationFacets.length; i++) {
    const facet = annotationFacets[i]
    const facetCrossfilter = cellCrossfilter.dimension(d => d.facetIndex[i])
    cellsByFacet[facet] = facetCrossfilter
  }
  return cellsByFacet
}

/** Initialize crossfilter, return cells by facet */
function initCrossfilter(facetData) {
  const { cells, facets } = facetData
  const annotationFacets = facets.map(facet => facet.annotation)
  const filterableCells = []

  for (let i = 0; i < cells.length; i++) {
    const filterableCell = { 'allCellsIndex': i }

    // An array of integers, e.g. [6, 0, 7, 0, 0]
    // Each element in the array is the index-offset of the cell's group value assignment
    // for the annotation facet at that index.
    const facetIndex = cells[i]
    filterableCell.facetIndex = facetIndex
    filterableCells.push(filterableCell)
  }

  const cellsByFacet = getCellsByFacet(filterableCells, annotationFacets)

  const filterCounts = getFilterCounts(annotationFacets, cellsByFacet, facets, null)

  const filtersByFacet = {}
  facets.forEach(facet => {
    filtersByFacet[facet.annotation] = facet.groups
  })

  return {
    filterableCells, cellsByFacet, loadedFacets: facets, filtersByFacet,
    filterCounts
  }
}

/** Determine which facets to fetch data for; helps load 1 batch at a time */
function getFacetsToFetch(allRelevanceSortedFacets, prevCellFaceting) {
  if (!prevCellFaceting) {
    return allRelevanceSortedFacets
      .map(annot => annot.annotation)
      .slice(0, 5)
  }

  // Get index of first facet that hasn't been loaded yet
  let fetchOffset = 0
  prevCellFaceting.facets.find((facet, i) => {
    if (!facet.isLoaded) {
      fetchOffset = i
      return true
    }
  })

  return allRelevanceSortedFacets
    .map(annot => annot.annotation)
    .slice(fetchOffset, fetchOffset + 5)
}

/** Log metrics to Mixpanel if fully loaded, return next perfTime object to pass in chain */
function logInitCellFaceting(timeStart, perfTimes, cellFaceting, prevCellFaceting) {
  const timeEnd = Date.now()
  perfTimes.perfTime = timeEnd - timeStart
  if (prevCellFaceting) {
    perfTimes.perfTime += prevCellFaceting.perfTimes.perfTime
    perfTimes.fetch += prevCellFaceting.perfTimes.fetch
    perfTimes.initCrossfilter += prevCellFaceting.perfTimes.initCrossfilter
    perfTimes.trimNullFilters += prevCellFaceting.perfTimes.trimNullFilters
    perfTimes.numInits = prevCellFaceting.perfTimes.numInits + 1
  } else {
    perfTimes.numInits = 1
  }

  if (cellFaceting.isFullyLoaded) {
    const logProps = {
      'numCells': cellFaceting.filterableCells.length,
      'numFacets': cellFaceting.facets.length,
      'numInits': perfTimes.numInits,
      'perfTime': perfTimes.perfTime,
      'perfTime:fetch': perfTimes.fetch,
      'perfTime:initCrossfilter': perfTimes.initCrossfilter,
      'perfTime:trimNullFilters': perfTimes.trimNullFilters
    }
    log('init-cell-faceting', logProps)
  }

  return perfTimes
}

/** Get 5 default annotation facets: 1 for selected, and 4 others */
export async function initCellFaceting(
  selectedCluster, selectedAnnot, studyAccession, allAnnots, prevCellFaceting
) {
  let perfTimes = {}
  const timeStart = Date.now()

  // Prioritize and fetch annotation facets for all cells
  const selectedAnnotId = getIdentifierForAnnotation(selectedAnnot)
  const eligibleAnnots =
    getGroupAnnotationsForClusterAndStudy(allAnnots, selectedCluster)
      .map(annot => { // Add identifiers to incoming annotations
        annot.identifier = getIdentifierForAnnotation(annot)
        return annot
      })
      .filter(annot => {
        return (
          annot.values.length > 1 &&
          !annot.identifier.endsWith('invalid') &&
          !annot.identifier.endsWith('user') &&
          annot.identifier !== selectedAnnotId
        )
      })

  const allRelevanceSortedFacets =
    sortAnnotationsByRelevance(eligibleAnnots)
      .map(annot => {
        return { annotation: annot.identifier, groups: annot.values }
      })

  if (allRelevanceSortedFacets.length === 0) {
    throw Error('Only 1 eligible annotation is in this clustering; filtering needs > 1')
  }

  const facetsToFetch = getFacetsToFetch(allRelevanceSortedFacets, prevCellFaceting)

  const timeFetchStart = Date.now()
  const newRawFacets = await fetchAnnotationFacets(studyAccession, facetsToFetch, selectedCluster)
  perfTimes.fetch = Date.now() - timeFetchStart

  // Below line is worth keeping, but only uncomment to debug in development.
  // This helps simulate waiting on server response, even when using local
  // service worker caching.
  //
  // await new Promise(resolve => setTimeout(resolve, 3000))

  const rawFacets = mergeFacetsResponses(newRawFacets, prevCellFaceting)

  const timeInitCrossfilterStart = Date.now()
  const {
    filterableCells, cellsByFacet,
    loadedFacets, filtersByFacet, filterCounts
  } = initCrossfilter(rawFacets)
  perfTimes.initCrossfilter = Date.now() - timeInitCrossfilterStart

  const facets = allRelevanceSortedFacets.map(facet => {
    const isLoaded = loadedFacets.some(loadedFacet => facet.annotation === loadedFacet.annotation)
    facet.isLoaded = isLoaded
    return facet
  })

  // Have all eligible annotations been loaded with faceting data?
  const isFullyLoaded = loadedFacets.length >= allRelevanceSortedFacets.length

  const rawCellFaceting = {
    filterableCells,
    cellsByFacet,
    facets,
    filtersByFacet,
    isFullyLoaded,
    rawFacets,
    filterCounts
  }

  const timeTrimNullFiltersStart = Date.now()
  const cellFaceting = trimNullFilters(rawCellFaceting)
  perfTimes.trimNullFilters = Date.now() - timeTrimNullFiltersStart

  perfTimes = logInitCellFaceting(timeStart, perfTimes, cellFaceting, prevCellFaceting)
  cellFaceting.perfTimes = perfTimes

  // Below line is worth keeping, but only uncomment to debug in development
  // window.SCP.cellFaceting = cellFaceting
  return cellFaceting
}

