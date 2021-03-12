import React from 'react'
import _clone from 'lodash/clone'
import Select from 'react-select'

import { annotationKeyProperties, getMatchedAnnotation, clusterSelectStyle } from 'lib/cluster-utils'

/** takes the server response and returns annotation options suitable for react-select */
function getAnnotationOptions(annotationList, clusterName) {
  return [{
    label: 'Study Wide',
    options: annotationList.annotations
      .filter(annot => annot.scope == 'study').map(annot => annotationKeyProperties(annot))
  }, {
    label: 'Cluster-Based',
    options: annotationList.annotations
      .filter(annot => annot.cluster_name === clusterName && annot.scope === 'cluster')
      .map(annot => annotationKeyProperties(annot))
  }, {
    label: 'User-Based',
    options: annotationList.annotations
      .filter(annot => annot.cluster_name === clusterName && annot.scope === 'user')
      .map(annot => annotationKeyProperties(annot))
  }]
}


/**
  Renders an annotation selector.
   the cluster is changed.
    @param annotationList: the results of a call to scpApi/fetchClusterOptions (or equivalent).
    @param cluster: the name of the cluster selected
    @param annotation: object specifying name, type and scope
    @param updateClusterParams: update function that accepts changes to cluster, annotation, and/or subsample properties
  */
export default function AnnotationControl({
  annotationList,
  cluster,
  annotation,
  updateClusterParams
}) {
  if (!annotationList) {
    annotationList = { default_cluster: null, default_annotation: null, annotations: [] }
  }

  const annotationOptions = getAnnotationOptions(annotationList, cluster)

  const shownAnnotation = _clone(annotation)
  // for user annotations, we have to match the given id to a name to show the name in the dropdown
  if (annotation && annotation.scope === 'user') {
    const matchedAnnotation = getMatchedAnnotation(annotation, annotationList)
    if (matchedAnnotation) {
      shownAnnotation.name = matchedAnnotation.name
      shownAnnotation.id = matchedAnnotation.id
    }
  }

  return (
    <div className="form-group">
      <label>Annotation</label>
      <Select options={annotationOptions}
        value={shownAnnotation}
        getOptionLabel={annotation => annotation.name}
        getOptionValue={annotation => annotation.scope + annotation.name + annotation.cluster_name}
        onChange={newAnnotation => updateClusterParams({ annotation: newAnnotation })}
        styles={clusterSelectStyle}/>
    </div>
  )
}
