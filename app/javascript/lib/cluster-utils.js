/** Utility functions for parsing cluster and annotation parameters from the server
 *  These live in a separate utility because multiple endpoints (explore, cluster, etc..)
 *  return annotationLists of the same basic structure */
import _clone from 'lodash/clone'

/** custom styling for cluster control-style select */
export const clusterSelectStyle = {
  control: provided => ({
    ...provided,
    borderColor: '#4d72aa'
  })
}

export const emptyDataParams = {
  cluster: '',
  annotation: '',
  subsample: '',
  consensus: null
}

export const UNSPECIFIED_ANNOTATION_NAME = '--Unspecified--'

/** takes the server response and returns subsample default subsample for the cluster */
export function getDefaultSubsampleForCluster(annotationList, clusterName) {
  const subsampleOptions = annotationList.subsample_thresholds[clusterName]
  if (subsampleOptions?.length) {
    // find the max subsample less than or equal to 100000
    const defaultSubsample = Math.max(...subsampleOptions.filter(opt => opt <= 100000))
    // if it's 100000, that means the study has more than 100000 cells, and so the
    // default is to show 100000.  otherwise we'll show all cells by default
    if (defaultSubsample === 100000) {
      return 100000
    }
  }
  return 'all'
}


/** takes a full annotation object, which may have values and other properties, and just extracts the
  * key parameters for url state */
export function annotationKeyProperties(annotation) {
  return {
    name: getAnnotationDisplayName(annotation),
    type: annotation.type,
    scope: annotation.scope,
    id: annotation.id,
    isDisabled: annotation.scope === 'invalid'
  }
}

/** returns a display name for an annotation to use in the select menu
 *
 * @param annotation - annotation object
 */
export function getAnnotationDisplayName(annotation) {
  if (annotation.scope === 'invalid') {
    let annotLabel = ''
    if (annotation.values.length === 1) {
      annotLabel = 'Only one value'
    } else if (annotation.values.length === 0) {
      // if the values array is empty, that means there were too many to send
      annotLabel = 'Too many values'
    } else {
      annotLabel = 'Ontology label used'
    }
    return `${annotation.name} (${annotLabel})`
  } else {
    return annotation.name
  }
}

/** Transforms annotation object to string identifier of form {name}--{type}--{scope} */
export function getIdentifierForAnnotation(annotation) {
  if (!annotation) {
    return '----'
  }
  return `${annotation.id ? annotation.id : annotation.name}--${annotation.type}--${annotation.scope}`
}

/** Transforms string identifier of {name}--{type}--{scope} to annotation object */
export function getAnnotationForIdentifier(identifier) {
  if (!identifier) {
    return null
  }
  const splitId = identifier.split('--')
  let annotation = { name: '', type: '', scope: '' }
  if (splitId.length > 1) {
    annotation = {
      name: splitId[0],
      type: splitId[1],
      scope: splitId[2]
    }
  }
  return annotation
}


/** extracts default parameters from an annotationList of the type returned by the explore API */
export function getDefaultClusterParams(annotationList, spatialGroups) {
  const defaultCluster = annotationList.default_cluster
  const clusterParams = {
    cluster: defaultCluster,
    annotation: annotationKeyProperties(annotationList.default_annotation),
    subsample: getDefaultSubsampleForCluster(annotationList, annotationList.default_cluster),
    spatialGroups: getDefaultSpatialGroupsForCluster(defaultCluster, spatialGroups)
  }
  return clusterParams
}

/** returns the first annotation for the given cluster */
export function getDefaultAnnotationForCluster(annotationList, clusterName, currentAnnotation) {
  if (currentAnnotation && currentAnnotation.scope === 'study') {
    // if they are changing cluster, and using a study-wide annotation, keep that annotation selected
    return currentAnnotation
  }
  const clusterAnnots = annotationList.annotations.filter(annot => annot.cluster_name === clusterName &&
                                                                   annot.scope === 'cluster')
  if (clusterAnnots.length) {
    return clusterAnnots[0]
  } else {
    return annotationList.annotations[0]
  }
}

/** return an array of names of the spatial files associated with a given cluster */
export function getDefaultSpatialGroupsForCluster(clusterName, spatialGroups) {
  const defaultGroups = []
  if (clusterName.length > 0 && spatialGroups && spatialGroups.length) {
    spatialGroups.forEach(group => {
      if (group.associated_clusters.includes(clusterName)) {
        defaultGroups.push(group.name)
      }
    })
  }
  return defaultGroups
}

/** finds the corresponding entry in annotationList for the given annotation,
 * and returns the unique values for the anotations
 */
export function getAnnotationValues(annotation, annotationList) {
  const matchedAnnotation = getMatchedAnnotation(annotation, annotationList)
  if (matchedAnnotation) {
    return matchedAnnotation.values
  }
  return []
}

/** Find matching entry in annotation list for specified annotation */
function getMatchedAnnotation(annotation, annotationList) {
  if (annotationList && annotationList.annotations) {
    const matchedAnnotation = annotationList.annotations.find(a => {
      return (a.name === annotation.name || a.id === annotation.name) &&
             a.type === annotation.type &&
             a.scope === annotation.scope
    })
    return matchedAnnotation
  }
  return null
}

/** Get display value for annotation drop-down menu, including user annotations */
export function getShownAnnotation(annotation, annotationList) {
  const shownAnnotation = _clone(annotation)
  // for user annotations, we have to match the given id to a name to show the name in the dropdown
  if (annotation && annotation.scope === 'user') {
    const matchedAnnotation = getMatchedAnnotation(annotation, annotationList)
    if (matchedAnnotation) {
      shownAnnotation.name = matchedAnnotation.name
      shownAnnotation.id = matchedAnnotation.id
    }
  }
  return shownAnnotation
}
