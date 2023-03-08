import React from 'react'

import {
  getDefaultSubsampleForCluster, annotationKeyProperties,
  getDefaultAnnotationForCluster, clusterSelectStyle
} from '~/lib/cluster-utils'
import Select from '~/lib/InstrumentedSelect'


/** takes the server response and returns cluster options suitable for react-select */
function getClusterOptions(annotationList, spatialGroups) {
  const clusterList = annotationList.clusters ? annotationList.clusters : []
  if (spatialGroups && spatialGroups.length) {
    // return two option groups, one non-spatial and one spatial
    const spatialGroupNames = spatialGroups.map(group => group.name)
    return [{
      options: clusterList.filter(name => !spatialGroupNames.includes(name))
        .map(name => ({ label: name, value: name }))
    }, {
      label: 'Spatial',
      options: clusterList.filter(name => spatialGroupNames.includes(name))
        .map(name => ({ label: name, value: name }))
    }]
  }
  return clusterList.map(name => {return { label: name, value: name }})
}


/**
  Renders a cluster selector.  Handles automatically updating the annotation and subsample when
   the cluster is changed.
    @param annotationList: the results of a call to scpApi/fetchClusterOptions (or equivalent).
    @param spatialGroups: the list of spatialGroups from exploreInfo
    @param cluster: the name of the cluster selected
    @param annotation: object specifying name, type and scope
    @param updateClusterParams: update function that accepts changes to cluster, annotation, and/or subsample properties
  */
export default function ClusterSelector({
  annotationList,
  spatialGroups,
  cluster,
  annotation,
  updateClusterParams,
  hasSelection=true
}) {
  if (!annotationList) {
    annotationList = { default_cluster: null, default_annotation: null, annotations: [] }
  }

  const clusterOptions = getClusterOptions(annotationList, spatialGroups)

  return (
    <div className="form-group">
      <label className="labeled-select">Clustering
        {hasSelection &&
          <Select options={clusterOptions}
            value={{ label: cluster, value: cluster }}
            data-analytics-name="cluster-select"
            onChange={newCluster => updateClusterParams({
              annotation: annotationKeyProperties(getDefaultAnnotationForCluster(
                annotationList,
                newCluster.value,
                annotation
              )),
              cluster: newCluster.value,
              subsample: getDefaultSubsampleForCluster(annotationList, newCluster.value)
            })}
            styles={clusterSelectStyle}
          />
      }
      {!hasSelection &&
        <Select
          menuIsOpen={true}
          placeholder="Select..."
          options={clusterOptions}
          data-analytics-name="cluster-select-differential-expression"
          onChange={newCluster => {
            updateClusterParams({
              annotation: annotationKeyProperties(getDefaultAnnotationForCluster(
                annotationList,
                newCluster.value,
                annotation
              )),
              cluster: newCluster.value,
              subsample: getDefaultSubsampleForCluster(annotationList, newCluster.value)
            })
          }}
        styles={clusterSelectStyle}
      />
      }
      </label>
    </div>
  )
}
