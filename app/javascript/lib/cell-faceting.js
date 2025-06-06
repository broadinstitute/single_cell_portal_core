/**
 * @fileoverview Library to enable fast client-side filtering of plotted cells
 *
 * Explainer: https://github.com/broadinstitute/single_cell_portal_core/pull/1862
 */

import crossfilter from 'crossfilter2'
import _isEqual from 'lodash/isEqual'

import { getIdentifierForAnnotation } from '~/lib/cluster-utils'
import { fetchAnnotationFacets } from '~/lib/scp-api'
import { log } from '~/lib/metrics-api'
import { round } from '~/lib/metrics-perf'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'

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
  const numFacets = Object.keys(selection).length
  const numFiltersSelected = Object.values(selection).reduce((numFilters, selectedFiltersForThisFacet) => {
    // return accumulator (an integer) + current value (an array, specifically its length)
    return numFilters + selectedFiltersForThisFacet?.length
  }, 0)

  const filterLogProps = {
    'perfTime': filterPerfTime,
    'perfTime:counts': perfTimeCounts,
    numCellsBefore,
    numCellsAfter,
    numFacets,
    numFiltersSelected
  }

  // Log to Mixpanel
  log('filter-cells', filterLogProps)
}

/**
 * Determine if a cell satisfies any numeric filters
 *
 * @param {Number} d - A numeric datum; a numeric annotation value for a cell
 * @param {Array<Array<String, *>>} numericFilters Filters for a numeric
 *   facet. Each filter has an operator and a value.  Values can be a number
 *   or an array of two numbers.
 *
 *   Example simple numeric filters:
 *   - ["=", 1.3]
 *   - ["!=", 1.3]
 *   - [">", 6]
 *   - [">=", 6]
 *   - ["<", 6]
 *   - ["<=", 6]
 *   - ["between", [5, 42]] -- inclusive, i.e. 5 <= d <= 42
 *   - ["not between", [5, 42]] -- inclusive, i.e. !(5 <= d <= 42)
 *
 *   Example compound numeric filters:
 *   - [["between", [95, 100]], ["between", [1200, 1300]] -- (95 <= d <= 100) or (1200 <= d <= 1300)
 *
 *   Compound numeric filters could be used to e.g.:
 *     - isolate the peaks of multimodal distributions (as in above concrete example)
 *     - isolate the tails of distributions
 *
 *   TODO:
 *   - Enable percentile filtering, i.e. beyond raw values.  Requires 1-time full sort, then trivial.
 *
 * @returns {Boolean} Whether cell datum passed any filters
 */
export function applyNumericFilters(d, rawFilters) {
  const [numericFilters, includeNa] = rawFilters

  if (includeNa && d === null) {return true}

  for (let i = 0; i < numericFilters.length; i++) {
    const [operator, value] = numericFilters[i]
    if (operator === '=') {
      // for fastest querying, exit function immediately upon _any_ condition
      // evaluating to true
      if (d === value) {return true}
    } else if (operator === '!=') {
      if (d !== value) {return true}
    } else if (operator === '>') {
      if (d > value) {return true}
    } else if (operator === '>=') {
      if (d >= value) {return true}
    } else if (operator === '<') {
      if (d < value) {return true}
    } else if (operator === '<=') {
      if (d <= value) {return true}
    } else if (operator === 'between') {
      if (value[0] <= d && d <= value[1]) {return true}
    } else if (operator === 'not between') {
      if (!(value[0] <= d && d <= value[1])) {return true}
    }
  }

  return false
}

/** Get filtered cell results */
export function filterCells(
  selection, cellsByFacet, initFacets, filterableCells, rawFacets
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
      if (facet in selection) {
        if (facet.includes('--group--')) {
          // e.g. 'infant_sick_YN'
          const friendlyFilters = selection[facet] // e.g. ['yes', 'NA']

          const filter = new Set()
          friendlyFilters.forEach(friendlyFilter => {
            // find the original index of the filter in the source annotation as the list here may be trimmed already
            const sourceFacet = rawFacets.find(f => f.annotation === facet)
            const filterIndex = sourceFacet.groups.indexOf(friendlyFilter)
            filter.add(filterIndex)
          })

          fn = function(d) {
            return filter.has(d)
          }

          // Apply the actual crossfilter method
          cellsByFacet[facet].filterFunction(fn)
        } else {
          // Numeric facet, e.g. time_post_partum_days
          // Example via console interface:
          // window.SCP.updateFilteredCells({'time_post_partum_days--numeric--study': [[0.5, 9]]})
          const numericFilters = selection[facet] // e.g. [0, 20]

          if (numericFilters === undefined) {
            // Some numeric annotations can have 1 (and only 1) value repeated
            // for every cell.  Such annotations are not eligible as facets,
            // because filtering requires > 1 value.
            //
            // TODO (SCP-5513): Screen numeric facets with constant value
            continue
          }

          fn = function(d) {
            return applyNumericFilters(d, numericFilters)
          }
          cellsByFacet[facet].filterFunction(fn)
        }
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

/**
 * Omit facets and cells that are all null, which can happen in numeric facets
 *
 * Example null facet:
 *  - SCP1671: ext_weight_during_study_lbs--numeric--study
 *
 * TODO (SCP-5513): Delete in MongoDB: numeric annotations with all null values
 */
function trimNullFacets(newRawFacets) {
  const allNonNullFacetIndexes = new Set()

  const numericFacetIndexes = []
  newRawFacets.facets.forEach((f, i) => {
    if (f.annotation.includes('--numeric--')) {
      numericFacetIndexes.push(i)
    } else {
      allNonNullFacetIndexes.add(i)
    }
  })

  if (numericFacetIndexes.length === 0) {
    return [newRawFacets, []]
  }

  const facets = []
  const cells = []

  for (let i = 0; i < newRawFacets.cells.length; i++) {
    const outerCellArray = newRawFacets.cells[i]
    for (let j = 0; j < numericFacetIndexes.length; j++) {
      const numericFacetIndex = numericFacetIndexes[j]
      if (allNonNullFacetIndexes.has(numericFacetIndex)) {continue}
      if (outerCellArray[numericFacetIndex] !== null) {
        allNonNullFacetIndexes.add(numericFacetIndex)
      }
    }
  }

  const sortedNonNullFacetIndexes = Array.from(allNonNullFacetIndexes).sort()
  const nullFacets =
    newRawFacets.facets
      .filter((f, i) => !sortedNonNullFacetIndexes.includes(i))
      .map(f => f.annotation)
  if (sortedNonNullFacetIndexes.length === 0) {
    return [{ cells, facets }, nullFacets]
  }
  for (let i = 0; i < newRawFacets.facets.length; i++) {
    if (allNonNullFacetIndexes.has(i)) {
      facets.push(newRawFacets.facets[i])
    }
  }
  for (let i = 0; i < newRawFacets.cells.length; i++) {
    const outerCellArray = newRawFacets.cells[i]
    const newOuterCellArray = []
    for (let j = 0; j < sortedNonNullFacetIndexes.length; j++) {
      const nonNullFacetIndex = sortedNonNullFacetIndexes[j]
      newOuterCellArray.push(outerCellArray[nonNullFacetIndex])
    }
    cells.push(newOuterCellArray)
  }

  return [{ cells, facets }, nullFacets]
}


/** Merge /facets responses from new and all prior batches */
function mergeFacetsResponses(newRawFacets, prevCellFaceting) {
  const nullTrimmedFacets = trimNullFacets(newRawFacets)
  newRawFacets = nullTrimmedFacets[0]
  const nullFacets = nullTrimmedFacets[1] // number of null facets in newRawFacets

  if (!prevCellFaceting) {
    return [newRawFacets, nullFacets]
  }

  const prevRawFacets = prevCellFaceting.rawFacets

  const facets = prevRawFacets.facets.concat(newRawFacets.facets)

  const cells = []
  for (let i = 0; i < prevRawFacets.cells.length; i++) {
    cells.push(prevRawFacets.cells[i].concat(newRawFacets.cells[i]))
  }

  const mergedRawFacets = { cells, facets }
  return [mergedRawFacets, nullFacets]
}

/** Get minimum and maximum value range for numeric filters, rounded to 2 decimal places */
export function getMinMaxValues(filters) {
  const firstValue = filters[0][0]
  const hasNull = firstValue === null
  const rawMinValue = hasNull ? filters[1][0] : firstValue
  const minValue = round(rawMinValue, 2)
  const rawMaxValue = filters.slice(-1)[0][0]
  const maxValue = round(rawMaxValue, 2)
  return [minValue, maxValue, hasNull]
}

/** Omit any filters that match 0 cells in the current clustering */
function trimNullFilters(cellFaceting) {
  const filterCountsByFacet = cellFaceting.filterCounts
  const facets = cellFaceting.facets.map(facet => facet.annotation)
  const nonzeroFiltersByFacet = {} // filters to remove, as they match no cells
  const nonzeroFilterCountsByFacet = {}
  const originalFacets = cellFaceting.rawFacets.facets

  let hasAnyNullFilters = false

  const filterableCells = cellFaceting.filterableCells

  for (let i = 0; i < facets.length; i++) {
    const facet = facets[i]
    const sourceFacet = originalFacets.find(f => f.annotation === facet)
    let facetHasNullFilter = false
    const isGroupFacet = facet.includes('--group--')
    let nullFilterIndex

    const countsByFilter = filterCountsByFacet[facet]

    const nonzeroFilters = []
    let defaultSelection = []
    const nonzeroFilterCounts = {}
    if (!countsByFilter) {
      continue
    }

    if (isGroupFacet) {
      Object.entries(countsByFilter).forEach(([filter, count], filterIndex) => {
        if (count !== null) {
          nonzeroFilters.push(filter)
          defaultSelection.push(filter)
          nonzeroFilterCounts[filter] = countsByFilter[filter]
        } else {
          facetHasNullFilter = true

          hasAnyNullFilters = true
          nullFilterIndex = filterIndex
        }
      })
    } else {
      Object.values(countsByFilter).forEach(([value, count], _) => {
        nonzeroFilters.push([value, count])
        nonzeroFilterCounts[value] = count
      })

      if (nonzeroFilters.length > 1) {
        const sortedNonzeroFilters = nonzeroFilters.sort((a, b) => a[0] - b[0])
        const [minValue, maxValue, _] = getMinMaxValues(sortedNonzeroFilters)
        const includeNa = true // Include any cells with "N/A" numeric values
        defaultSelection = [[['between', [minValue, maxValue]]], includeNa]
      } else {
        // Omit numeric annotations that have 1 or 0 values
        continue
      }
    }

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
    cellFaceting.facets[i].defaultSelection = defaultSelection
    if (typeof sourceFacet !== 'undefined') {
      cellFaceting.facets[i].originalGroups = sourceFacet.groups
    }
  }

  if (!hasAnyNullFilters) {return cellFaceting}

  cellFaceting.cellsByFacet = getCellsByFacet(filterableCells, facets)
  cellFaceting.filterableCells = filterableCells
  cellFaceting.filterCounts = nonzeroFilterCountsByFacet

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
    let countsByFilter

    if (facet.includes('--group--')) {
      countsByFilter = {}
      facets[i].groups?.forEach((group, j) => {
        let count = null
        // check for originalGroups array first, if present
        const originalGroups = facets[i].originalGroups || facets[i].groups
        const groupIdx = originalGroups.indexOf(group)
        const rawFilterKeyAndValue = rawFilterCounts.find(rfc => rfc.key === groupIdx)
        if (rawFilterKeyAndValue) {
          count = rawFilterKeyAndValue.value
        }
        countsByFilter[group] = count
      })
    } else {
      countsByFilter = []
      for (let j = 0; j < rawFilterCounts.length; j++) {
        // For numeric facets, `rawFilterCounts` is an array of objects, where
        // each object is a distinct numeric value observed in the facet;
        // the `key` of this object is the numeric value, and the `value` is
        // how many cells were observed with that numeric value.
        const countObject = rawFilterCounts[j]
        const filterValueAndCount = [countObject.key, countObject.value]
        countsByFilter.push(filterValueAndCount)
      }

      // Sort array by numeric value, to aid later histogram, etc.
      countsByFilter = countsByFilter.sort((a, b) => a[0] - b[0])
    }
    filterCounts[facet] = countsByFilter
  }

  // If a filter has been deselected, set its count to 0
  if (selection) {
    Object.entries(filterCounts).forEach(([facet, countsByFilter]) => {
      Object.entries(countsByFilter).forEach(([filter, count]) => {
        let newCount = count
        if (!(facet in selection && selection[facet]?.includes(filter))) {
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

    // For group-baesd annotations, we have an array of integers, e.g. [6, 0, 7, 0, 0].
    // Each element in the array is the index-offset of the cell's group value assignment
    // for the annotation facet at that index.
    const facetIndex = cells[i]
    filterableCell.facetIndex = facetIndex
    filterableCells.push(filterableCell)
  }

  const cellsByFacet = getCellsByFacet(filterableCells, annotationFacets)

  const filterCounts = getFilterCounts(annotationFacets, cellsByFacet, facets, null)

  return {
    filterableCells, cellsByFacet, loadedFacets: facets,
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

  const facetsToFetch = allRelevanceSortedFacets
    .map(annot => annot.annotation)
    .slice(fetchOffset, fetchOffset + 5)

  return facetsToFetch
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

/** Get annotations that can be filtered */
function getFilterableAnnotationsForClusterAndStudy(annotations, clusterName) {
  const annots = annotations.filter(annot => {
    return (
      (
        !('cluster_name' in annot) || // is study-wide
        annot.cluster_name === clusterName // is cluster-based, and in this cluster
      )
    )
  })
  return annots
}

/** Omit annotations that are CELLxGENE term IDs */
function getIsCellxGeneTermId(annotName) {
  const isCellxGeneTermId = [
    'disease_ontology_term_id',
    'cell_type_ontology_term_id',
    'library_preparation_protocol_term_id',
    'sex_ontology_term_id',
    'protocol_URL',
    'tissue_ontology_term_id',
    'assay_ontology_term_id',
    'development_stage_ontology_term_id'
  ].includes(annotName)

  return isCellxGeneTermId
}

/** Get 5 default annotation facets: 1 for selected, and 4 others */
export async function initCellFaceting(
  selectedCluster, selectedAnnot, studyAccession, allAnnots, prevCellFaceting, subsample=null
) {
  let perfTimes = {}
  const timeStart = Date.now()

  const flags = getFeatureFlagsWithDefaults()
  const shouldHideNumericCellFiltering = !flags?.show_numeric_cell_filtering

  // Prioritize and fetch annotation facets for all cells
  const selectedAnnotId = getIdentifierForAnnotation(selectedAnnot)
  const eligibleAnnots =
    getFilterableAnnotationsForClusterAndStudy(allAnnots, selectedCluster)
      .map(annot => { // Add identifiers to incoming annotations
        annot.identifier = getIdentifierForAnnotation(annot)
        return annot
      })
      .filter(annot => {
        return (
          !(annot.type === 'group' && annot.values.length <= 1) &&
          !annot.identifier.endsWith('invalid') &&
          !annot.identifier.endsWith('user') &&
          !(annot.type === 'numeric' && shouldHideNumericCellFiltering) &&
          !(getIsCellxGeneTermId(annot.name))
        )
      })

  let allRelevanceSortedFacets =
    sortAnnotationsByRelevance(eligibleAnnots)
      .filter(annot => {
        if (!prevCellFaceting) {
          return true
        }

        const prevAnnotFacets = prevCellFaceting.facets.map(f => f.annotation)

        // Omit null facets detected in prior calls of `initCellFaceting`
        return (prevAnnotFacets.includes(annot.identifier))
      })
      .map(annot => {
        const facet = { annotation: annot.identifier, type: annot.type }
        if (annot.type) {
          annot.group = annot.values
        }
        return facet
      })

  if (allRelevanceSortedFacets.length === 0) {
    throw Error('Only 1 eligible annotation is in this clustering; filtering needs > 1')
  }

  const facetsToFetch = getFacetsToFetch(allRelevanceSortedFacets, prevCellFaceting)

  const timeFetchStart = Date.now()
  const newRawFacets = await fetchAnnotationFacets(studyAccession, facetsToFetch, selectedCluster, selectedAnnotId, subsample)
  perfTimes.fetch = Date.now() - timeFetchStart

  // Below line is worth keeping, but only uncomment to debug in development.
  // This helps simulate waiting on server response, to slow data load even
  // when using local service worker caching.
  //
  // await new Promise(resolve => setTimeout(resolve, 3000))

  const [rawFacets, nullFacets] = mergeFacetsResponses(newRawFacets, prevCellFaceting)
  allRelevanceSortedFacets = allRelevanceSortedFacets.filter(f => !nullFacets.includes(f.annotation))

  const timeInitCrossfilterStart = Date.now()
  const {
    filterableCells, cellsByFacet,
    loadedFacets, filterCounts
  } = initCrossfilter(rawFacets)
  perfTimes.initCrossfilter = Date.now() - timeInitCrossfilterStart

  const facets = allRelevanceSortedFacets.map(facet => {
    const isLoaded = loadedFacets.some(loadedFacet => facet.annotation === loadedFacet.annotation)
    facet.isLoaded = isLoaded
    facet.isSelectedAnnotation = facet.annotation === selectedAnnotId
    return facet
  })

  // Have all eligible annotations been loaded with faceting data?
  const isFullyLoaded = loadedFacets.length >= allRelevanceSortedFacets.length

  const rawCellFaceting = {
    filterableCells,
    cellsByFacet,
    facets,
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

/** Parse `facets` URL parameter into cell filtering selection object */
export function parseFacetsParam(initFacets, facetsParam) {
  const selection = {}

  // Convert the `facets` parameter value, which is a string,
  // into an object that has the same shape as `selections`
  const facets = {}
  const innerParams = facetsParam.split(';')
  innerParams.forEach(innerParam => {
    const [facet, rawFilters] = innerParam.split(':')
    const filters = rawFilters.split('|')
    facets[facet] = filters
  })

  Object.entries(initFacets).forEach(([facet, filters]) => {
    if (facet.includes('group')) {
      // Take the complement of the minimal `facets` object, transforming
      // it into the more verbose `selection` object which specifies filters
      // that are _not_ applied.
        filters?.forEach(filter => {
          if (!facets[facet]?.includes(filter)) {
            if (facet in selection) {
              selection[facet].push(filter)
            } else {
              selection[facet] = [filter]
            }
          }
        })
    } else {
      const numericFiltersAndIncludeNa = facets[facet]
      if (numericFiltersAndIncludeNa) {
        const rawNumericFilters = numericFiltersAndIncludeNa.slice(0, -1)
        const [operator, rawVal, rawVal2] = rawNumericFilters[0].split(',')
        const value = parseFloat(rawVal)
        const value2 = parseFloat(rawVal2)
        let numericFilters
        if (['between', 'not between'].includes(operator)) {
          numericFilters = [[operator, [value, value2]]]
        } else {
          numericFilters = [[operator, value]]
        }
        const rawIncludeNa = numericFiltersAndIncludeNa.slice(-1)[0]
        const includeNa = rawIncludeNa === 'true'
        selection[facet] = [numericFilters, includeNa]
      }
    }
  })

  return selection
}

/** Construct `facets` URL parameter value, for cell filtering */
export function getFacetsParam(initFacets, selection) {
  const minimalSelection = {}

  const initSelection = {}
  initFacets.filter(f => !f.isSelectedAnnotation)?.forEach(facet => {
    initSelection[facet.annotation] = facet.defaultSelection
  })

  const innerParams = []

  Object.entries(initSelection).forEach(([facet, filters]) => {
    const facetObj = initFacets.find(f => f.annotation === facet)
    if (facetObj.type === 'group') {
      filters.forEach(filter => {
        // Unlike `selection`, which specifies all filters that are selected
        // (i.e., checked and not applied), the `facets` parameter species only
        // filters that are _not_ selected, i.e. they're unchecked and applied.
        //
        // This makes the `facets` parameter much clearer.
        if (!selection[facet].includes(filter)) {
          if (facet in minimalSelection) {
            minimalSelection[facet].push(filter)
          } else {
            minimalSelection[facet] = [filter]
          }
        }
      })
    } else {
      if (!_isEqual(initSelection[facet], selection[facet])) {
        // Add numeric cell facet to `facets` URL parameter
        minimalSelection[facet] = selection[facet]
      }
    }
  })

  Object.entries(minimalSelection).forEach(([facet, filters]) => {
    // TODO (SCP-5513): Screen numeric facets with constant value, then remove line below
    if (filters === undefined) {return}

    const innerParam = `${facet}:${filters.join('|')}`
    innerParams.push(innerParam)
  })

  const facetParams = innerParams.join(';')
  return facetParams
}

