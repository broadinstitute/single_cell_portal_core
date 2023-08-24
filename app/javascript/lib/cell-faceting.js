import {
  getGroupAnnotationsForClusterAndStudy, getIdentifierForAnnotation, getAnnotationForIdentifier
} from '~/lib/cluster-utils'
import { fetchAnnotationFacets } from '~/lib/scp-api'
import crossfilter from 'crossfilter2'


const CELL_TYPE_RE = new RegExp(/cell.*type/i)

// Detect if a string mentions disease, sickness, malignant or malignancy,
// indication, a frequent suffix of disease names, or a common suffix of cancer names
const DISEASE_RE = new RegExp(/(disease|sick|malignan|indicat|itis|osis|oma)/i)

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
 * Prioritization logic applied here, after above preconditions are met:
 *
 *   0. Not currently selected annotation -- this is set upstream, not here
 *   1. <= 2 annotations from metadata convention, for `cell type` and `disease`
 *   2. 0-5 annotations that are cell-type-like or disease-like
 *   2. 0-2 cluster-based annotations
 *   3. 0-5 study-wide annotations
 *
 * Annotations in above categories often don't exist, in which case we fall to the
 * the next prioritization rule.
 */
function prioritizeAnnotations(annotList) {
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
    annot => (CELL_TYPE_RE.test(annot.name) || DISEASE_RE.test(annot.name)) && isUnique(annot)
  )
  annotsToFacet = annotsToFacet.concat(cellTypeOrClinicalAnnots)

  const otherConventionalAnnots = annotList.filter(
    annot => annot.name.endsWith('__ontology_label') && isUnique(annot)
  ).slice(0, 2)
  annotsToFacet = annotsToFacet.concat(otherConventionalAnnots)

  const clusterAnnots = annotList.filter(
    annot => ('cluster_name' in annot) && isUnique(annot)
  )
  annotsToFacet = annotsToFacet.concat(clusterAnnots)

  const studyAnnots = annotList.filter(
    annot => !('cluster_name' in annot) && isUnique(annot)
  )
  annotsToFacet = annotsToFacet.concat(studyAnnots)

  annotsToFacet = annotsToFacet.map(annot => annot.identifier).slice(0, 5)

  return annotsToFacet
}

/** Get filtered cell results */
export function filterCells(
  selections, cellsByFacet, facets, filtersByFacet, filterableCells
) {
  facets = facets.map(facet => facet.annotation)

  let fn; let i; let facet; let results
  const counts = {}

  if (Object.keys(selections).length === 0) {
    results = filterableCells
  } else {
    for (i = 0; i < facets.length; i++) {
      facet = facets[i]
      if (facet in selections) { // e.g. 'infant_sick_YN'
        const friendlyFilters = selections[facet] // e.g. ['yes', 'NA']

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
    //  and get its `groups`.  Then the group value assignment would be the 6th string in the
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
  console.log('selectedCluster', selectedCluster),
  console.log('selectedAnnot', selectedAnnot)
  console.log('studyAccession', studyAccession)
  console.log('allAnnots', allAnnots)

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
          annot.identifier !== selectedAnnotId
        )
      })
  console.log('applicableAnnots', applicableAnnots)
  const annotsToFacet = prioritizeAnnotations(applicableAnnots)
  const facetData = await fetchAnnotationFacets(studyAccession, annotsToFacet, selectedCluster)
  console.log('facetData', facetData)

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
  console.log('cellFaceting', cellFaceting)
  return cellFaceting
}

