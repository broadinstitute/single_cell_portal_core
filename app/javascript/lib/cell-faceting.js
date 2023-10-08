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
const DISEASE_REGEX = new RegExp(/(disease|sick|malignan|indicat|itis|osis|oma)/i)

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

  const otherConventionalAnnots = annotList.filter(annot => {
    return (
      (
        annot.name.endsWith('__ontology_label') ||
        annot.name === 'donor_id' ||
        annot.name === 'biosample_id'
      ) && isUnique(annot)
    )
  })
  annotsToFacet = annotsToFacet.concat(otherConventionalAnnots)

  const clusterAnnots = annotList.filter(
    annot => ('cluster_name' in annot) && isUnique(annot)
  )
  annotsToFacet = annotsToFacet.concat(clusterAnnots)

  const studyAnnots = annotList.filter(
    annot => !('cluster_name' in annot) && isUnique(annot)
  )
  annotsToFacet = annotsToFacet.concat(studyAnnots)

  annotsToFacet = annotsToFacet.map(annot => annot.identifier)

  return annotsToFacet
}

/** Get filtered cell results */
export function filterCells(
  selection, cellsByFacet, facets, filtersByFacet, filterableCells
) {
  const t0 = Date.now()
  facets = facets.map(facet => facet.annotation)

  let fn; let i; let facet; let results
  const counts = {}

  if (Object.keys(selection).length === 0) {
    results = filterableCells
  } else {
    for (i = 0; i < facets.length; i++) {
      facet = facets[i]
      if (facet in selection) { // e.g. 'infant_sick_YN'
        const friendlyFilters = selection[facet] // e.g. ['yes', 'NA']

        const filter = {}
        friendlyFilters.forEach(friendlyFilter => {
          const filterIndex = filtersByFacet[facet].indexOf(friendlyFilter)
          filter[filterIndex] = 1
        })

        if (Array.isArray(filter)) {
          fn = function(d) {
            // Filter is numeric range
            if (filter.length === 2) {
              // [min, max]
              return filter[0] <= d && d < filter[1]
            } else if (filter.length === 4) {
              // [min1, max1, min2, max2]
              return (
                filter[0] <= d && d < filter[1] ||
                filter[2] <= d && d < filter[3]
              )
            }
          }
        } else {
          fn = function(d) {
            // Filter is set of categories
            return (d in filter)
          }
        }
      } else {
        fn = null
      }
      cellsByFacet[facet].filter(fn)
      counts[facet] = cellsByFacet[facet].group().top(Infinity)
    }
    results = cellsByFacet[facet].top(Infinity)
  }

  const t1 = Date.now()
  // Assemble analytics
  const filterPerfTime = t1 - t0
  const numCellsBefore = filterableCells.length
  const numCellsAfter = results.length
  const numFacetsSelected = Object.keys(selection).length
  const numFiltersSelected = Object.values(selection).length
  const filterLogProps = {
    perfTime: filterPerfTime,
    numCellsBefore,
    numCellsAfter,
    numFacetsSelected,
    numFiltersSelected,
    selection
  }

  // Log to Mixpanel
  log('filter-cells', filterLogProps)

  return [results, counts]
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
    //
    //  So, for the first element, `6`, we look up the element at index 0 in annotationFacets,
    //  and get its `groups`.  Then the group value assignment would be the 7th string in the
    //  `groups` array for the 0th annotation.
    const cellGroupIndexes = cells[i]
    for (let j = 0; j < cellGroupIndexes.length; j++) {
      const annotationIdentifier = annotationFacets[j]
      filterableCell[annotationIdentifier] = cellGroupIndexes[j]
    }
    filterableCells.push(filterableCell)
  }

  const cellCrossfilter = crossfilter(filterableCells)
  const cellsByFacet = {}
  for (let i = 0; i < annotationFacets.length; i++) {
    const facet = annotationFacets[i]
    cellsByFacet[facet] = cellCrossfilter.dimension(d => d[facet])
  }

  const filtersByFacet = {}
  facets.forEach(facet => {
    filtersByFacet[facet.annotation] = facet.groups
  })

  return { filterableCells, cellsByFacet, facets, filtersByFacet }
}

/** Get 5 default annotation facets: 1 for selected, and 4 others */
export async function initCellFaceting(
  selectedCluster, selectedAnnot, studyAccession, allAnnots
) {
  // Prioritize and fetch annotation facets for all cells
  const selectedAnnotId = getIdentifierForAnnotation(selectedAnnot)
  const applicableAnnots =
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

  const allRelevanceSortedFacets = sortAnnotationsByRelevance(applicableAnnots)
  const annotFacetsToLoad = allRelevanceSortedFacets.slice(0, 5)
  const facetData = await fetchAnnotationFacets(studyAccession, annotFacetsToLoad, selectedCluster)

  const {
    filterableCells, cellsByFacet,
    facets, filtersByFacet
  } = initCrossfilter(facetData)

  const cellFaceting = {
    filterableCells,
    cellsByFacet,
    selections: [],
    facets,
    filtersByFacet
  }

  // Below line is worth keeping, but only uncomment to debug in development
  // window.SCP.cellFaceting = cellFaceting
  return cellFaceting
}

