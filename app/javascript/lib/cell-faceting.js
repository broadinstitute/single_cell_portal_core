import { getAnnotationValues, getShownAnnotation } from '~/lib/cluster-utils'

/** Get 5 default annotation facets: 1 for selected, and 4 others */
export function fetchAnnotationFacets(selectedCluster, selectedAnnot, exploreInfo) {
  const annotList = exploreInfo.annotationList
  console.log('selectedCluster, selectedAnnot, exploreInfo', selectedCluster, selectedAnnot, exploreInfo)
}

window.SCP.fetchAnnotationFacets = fetchAnnotationFacets
