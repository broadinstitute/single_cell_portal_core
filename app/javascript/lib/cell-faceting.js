import {
  getGroupAnnotationsForClusterAndStudy, getIdentifierForAnnotation
} from '~/lib/cluster-utils'
import { fetchAnnotationFacetData } from '~/lib/scp-api'


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
 *   2. 2-4 other cluster-based annotations
 *   3. 2-4 other study-wide annotations
 *
 * Annotations in above categories often don't exist, in which case we fall to the
 * the next prioritization rule.
 */
function prioritizeAnnotations(annotList) {
  let annotsToFacet = []
  const seenAnnots = new Set()

  // Add identifiers to incoming annotations
  annotList = annotList.map(annot => {
    annot.identifier = getIdentifierForAnnotation(annot)
    return annot
  })
  console.log('0 annotList', annotList)

  const cellTypeAndDiseaseAnnots = annotList.filter(
    annot => ['cell_type__ontology_label', 'disease__ontology_label'].includes(annot.name)
  )
  cellTypeAndDiseaseAnnots.forEach(annot => seenAnnots.add(annot.identifier))
  annotsToFacet = annotsToFacet.concat(cellTypeAndDiseaseAnnots)

  const otherConventionalAnnots = annotList.filter(
    annot => annot.name.endsWith('__ontology_label') && !seenAnnots.has(annot.identifier)
  ).slice(0, 2)
  otherConventionalAnnots.forEach(annot => seenAnnots.add(annot.identifiers))
  annotsToFacet = annotsToFacet.concat(otherConventionalAnnots)

  const clusterAnnots = annotList.filter(
    annot => ('cluster_name' in annot) && !seenAnnots.has(annot.identifier)
  )
  clusterAnnots.forEach(annot => seenAnnots.add(annot.identifiers))
  annotsToFacet = annotsToFacet.concat(clusterAnnots)

  const studyAnnots = annotList.filter(
    annot => !('cluster_name' in annot) && !seenAnnots.has(annot.identifier)
  )
  studyAnnots.forEach(annot => seenAnnots.add(annot.identifiers))
  annotsToFacet = annotsToFacet.concat(studyAnnots)

  annotsToFacet =
    annotsToFacet
      .map(annot => annot.identifier)
      .slice(0, 5)

  return annotsToFacet
}

/** Get 5 default annotation facets: 1 for selected, and 4 others */
export async function fetchAnnotationFacets(
  selectedCluster, selectedAnnot, studyAccession, exploreInfo
) {
  const allAnnots = exploreInfo?.annotationList
  if (!allAnnots) {return}
  console.log('allAnnots', allAnnots)
  const applicableAnnots =
    getGroupAnnotationsForClusterAndStudy(allAnnots, selectedCluster)
      .filter(annotation => annotation.values.length > 1)
  console.log('applicableAnnots', applicableAnnots)
  const annotsToFacet = prioritizeAnnotations(applicableAnnots)
  console.log('selectedCluster, selectedAnnot', selectedCluster, selectedAnnot)
  console.log('annotsToFacet', annotsToFacet)
  const facets = await fetchAnnotationFacetData(studyAccession, annotsToFacet, selectedCluster)
  console.log('facets', facets)
}

window.SCP.fetchAnnotationFacets = fetchAnnotationFacets
