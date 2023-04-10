import React from 'react'

import Select from '~/lib/InstrumentedSelect'
import { annotationKeyProperties, clusterSelectStyle } from '~/lib/cluster-utils'

/** takes the server response and returns annotation options suitable for react-select */
function getAnnotationOptions(annotationList, clusterName) {
  return [{
    label: 'Study wide',
    options: annotationList.annotations
      .filter(annot => annot.scope === 'study').map(annot => annotationKeyProperties(annot))
  }, {
    label: 'Cluster-based',
    options: annotationList.annotations
      .filter(annot => annot.cluster_name === clusterName && annot.scope === 'cluster')
      .map(annot => annotationKeyProperties(annot))
  }, {
    label: 'User-based',
    options: annotationList.annotations
      .filter(annot => annot.cluster_name === clusterName && annot.scope === 'user')
      .map(annot => annotationKeyProperties(annot))
  }, {
    label: 'Cannot display',
    options: annotationList.annotations
      .filter(annot => annot.scope === 'invalid' && (annot.cluster_name == clusterName || !annot.cluster_name))
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
  shownAnnotation,
  updateClusterParams,
  hasSelection=true,
  setShowDifferentialExpressionPanel,
  setShowUpstreamDifferentialExpressionPanel
}) {
  if (!annotationList) {
    annotationList = { default_cluster: null, default_annotation: null, annotations: [] }
  }

  const annotationOptions = getAnnotationOptions(annotationList, cluster)

  return (
    <div className="form-group">
      <label className="labeled-select">Annotation
        {hasSelection &&
          <Select
            options={annotationOptions}
            data-analytics-name="annotation-select"
            value={shownAnnotation}
            isOptionDisabled={annotation => annotation.isDisabled}
            getOptionLabel={annotation => annotation.name}
            getOptionValue={annotation => annotation.scope + annotation.name + annotation.cluster_name}
            onChange={newAnnotation => updateClusterParams({ annotation: newAnnotation })}
            styles={clusterSelectStyle}/>
        }
        {!hasSelection &&
          <Select
            menuIsOpen={true}
            options={annotationOptions}
            data-analytics-name="annotation-select-differential-expression"
            getOptionLabel={annotation => annotation.name}
            getOptionValue={annotation => annotation.scope + annotation.name + annotation.cluster_name}
            onChange={newAnnotation => {
              updateClusterParams({ annotation: newAnnotation })
              setShowDifferentialExpressionPanel(true)
              setShowUpstreamDifferentialExpressionPanel(false)
            }}
            styles={clusterSelectStyle}/>
        }
      </label>
    </div>
  )
}
