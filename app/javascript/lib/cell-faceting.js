import {
  getGroupAnnotationsForClusterAndStudy, getIdentifierForAnnotation, getAnnotationForIdentifier
} from '~/lib/cluster-utils'
import { fetchAnnotationFacets } from '~/lib/scp-api'
import crossfilter from 'crossfilter2'


/**
 * Prioritize unselected annotations to those worth showing by default as facets
 *
 * To start, show <= 4 annotations (beyond the one current selected) facets by default.
 *
 * Preconditions -- annotations must be:
 *   - Group-based and have > 1 group
 *   - Cluster-based _and for this cluster_ or study-wide
 *
 * Prioritization logic applied here, after above preconditions are met:
 *
 *   0. Currently selected annotation -- this is set upstream, not here
 *   1. <= 2 annotations from metadata convention, for `cell type` and `disease`
 *   2. 0-2 cluster-based annotations
 *   3. 0-4 study-wide annotations
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

  const cellTypeAndDiseaseAnnots = annotList.filter(
    annot => ['cell_type__ontology_label', 'disease__ontology_label'].includes(annot.name)
  )
  annotsToFacet = annotsToFacet.concat(cellTypeAndDiseaseAnnots)

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
export function filterCells(selections, cellsByFacet, facets, filterableCells) {
  facets = facets.map(facet => facet.annotation)
  let fn; let i; let facet; let results; let filter
  const counts = {}

  if (Object.keys(selections).length === 0) {
    results = filterableCells
  } else {
    for (i = 0; i < facets.length; i++) {
      facet = facets[i]
      if (facet in selections) {
        filter = selections[facet]
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
  console.log('cellsByFacet', cellsByFacet)

  return { filterableCells, cellsByFacet }
}

/** Get 5 default annotation facets: 1 for selected, and 4 others */
export async function initCellFaceting(
  selectedCluster, selectedAnnot, studyAccession, exploreInfo,
  setCellFaceting
) {
  // Prioritize and fetch annotation facets for all cells
  const allAnnots = exploreInfo?.annotationList
  if (!allAnnots || allAnnots.annotations.length === 0) {return}


  const selectedAnnotId = getIdentifierForAnnotation(selectedAnnot)
  const applicableAnnots =
    getGroupAnnotationsForClusterAndStudy(allAnnots, selectedCluster)
      .map(annot => { // Add identifiers to incoming annotations
        annot.identifier = getIdentifierForAnnotation(annot)
        return annot
      })
      .filter(
        annot => annot.values.length > 1 && annot.identifier !== selectedAnnotId
      )

  console.log('applicableAnnots', applicableAnnots)
  const annotsToFacet = prioritizeAnnotations(applicableAnnots)
  const facetData = await fetchAnnotationFacets(studyAccession, annotsToFacet, selectedCluster)

  const { filterableCells, cellsByFacet } = initCrossfilter(facetData)

  setCellFaceting({
    cellsByFacet,
    annotFacetSelections: [],
    facets: facetData.facets,
    filterableCells
  })
}

