import React, { useState, useEffect } from 'react'
import _uniq from 'lodash/uniq'
import _find from 'lodash/find'
import Select from 'react-select'

import { fetchClusterOptions } from 'lib/scp-api'

const collapseOptions = [
  {label: 'None', value: null},
  {label: 'Mean', value: 'mean'},
  {label: 'Median', value: 'median'}
]

/** takes the server response and returns subsample options suitable for react-select */
function getSubsampleOptions(annotationList, clusterName) {
  let subsampleOptions = [{ label: 'All Cells', value: '' }]
  if (clusterName) {
    let clusterSubsamples = annotationList.subsample_thresholds[clusterName]
    if (!clusterSubsamples) {
      clusterSubsamples = []
    }
    subsampleOptions = subsampleOptions.concat(clusterSubsamples.map(num => {
      return { label: `${num}`, value: num }
    }))
  }
  return subsampleOptions
}

/** takes the server response and returns cluster options suitable for react-select */
function getClusterOptions(annotationList) {
  let clusterList = annotationList.clusters ? annotationList.clusters : []
  return clusterList.map(name => {return { label: name, value: name}})
}

/** takes the server response and returns annotation options suitable for react-select */
function getAnnotationOptions(annotationList, clusterName) {
  return [{
      label: 'Study Wide',
      options: annotationList.annotations
        .filter(annot => annot.scope == 'study')
    }, {
      label: 'Cluster-Based',
      options: annotationList.annotations
        .filter(annot => annot.cluster_name == clusterName)
  }]
}

/** returns the first annotation for the given cluster */
function getDefaultAnnotationForCluster(annotationList, clusterName, currentAnnotation) {
  if (currentAnnotation && currentAnnotation.scope === 'study') {
    // if they are changing cluster, and using a study-wide annotation, keep that annotation selected
    return currentAnnotation
  }
  const clusterAnnots = annotationList.annotations.filter(annot => annot.cluster_name == clusterName)
  if (clusterAnnots.length) {
    return clusterAnnots[0]
  } else {
    return annotationList.annotations[0]
  }

}

/** takes the server response and returns subsample default subsample for the cluster */
function getDefaultSubsampleForCluster(annotationList, clusterName) {
  return '' // for now, default is always all cells
}

/** renders cluster, annotation, and (optionally) subsample controls for a study */
export default function ClusterControls({studyAccession,
                                         onChange,
                                         showSubsample,
                                         preloadedAnnotationList,
                                         fetchAnnotationList=true,
                                         setCollapseBy,
                                         collapseBy}) {
  const [annotationList, setAnnotationList] =
    useState({ default_cluster: null, default_annotation: null, annotations: [] })
  const [renderParams, setRenderParams] = useState({
    userUpdated: false,
    cluster: '',
    annotation: '',
    subsample: ''
  })
  const clusterOptions = getClusterOptions(annotationList)
  const annotationOptions = getAnnotationOptions(annotationList, renderParams.cluster)
  const subsampleOptions = getSubsampleOptions(annotationList, renderParams.cluster)

  // override the default of interior scrollbars on the menu
  const customSelectStyle = {
    control: (provided) => ({
      ...provided,
      borderColor: '#4d72aa'
    })
  }


  function update(newAnnotationList) {
    setAnnotationList(newAnnotationList)
    const newRenderParams = {
      userUpdated: false,
      cluster: newAnnotationList.default_cluster,
      annotation: newAnnotationList.default_annotation,
      subsample: getDefaultSubsampleForCluster(newAnnotationList, newAnnotationList.default_cluster)
    }
    setRenderParams(newRenderParams)
  }

  useEffect(() => {
    // only update if this component is responsible for loading annotation data from the server
    // or if the preloadedList has been specified already
    if (fetchAnnotationList) {
      fetchClusterOptions(studyAccession).then(newAnnotationList => update(newAnnotationList))
    } else {
      if (preloadedAnnotationList) {
        update(preloadedAnnotationList)
      }
    }
  }, [studyAccession, preloadedAnnotationList])

  useEffect(() => {
    // don't fire the onchange on initial render
    if (renderParams.cluster !== '' && onChange) {
      onChange(renderParams)
    }
  }, [renderParams.cluster, renderParams.annotation.name, renderParams.subsample])

  return (
    <div>
      <div className="form-group">
        <label>Load cluster</label>
        <Select options={clusterOptions}
          value={{ label: renderParams.cluster, value: renderParams.cluster }}
          onChange={ cluster => setRenderParams({
            userUpdated: true,
            annotation: getDefaultAnnotationForCluster(annotationList, cluster.name, renderParams.annotation),
            cluster: cluster.value,
            subsample: getDefaultSubsampleForCluster(annotationList, cluster.value)
          })}
          styles={customSelectStyle}
        />
      </div>
      <div className="form-group">
        <label>Select annotation</label>
        <Select options={annotationOptions}
          value={renderParams.annotation}
          getOptionLabel={annotation => annotation.name}
          getOptionValue={annotation => annotation.scope + annotation.name + annotation.cluster_name}
          onChange={annotation => setRenderParams({
            userUpdated: true,
            annotation: annotation,
            cluster: renderParams.cluster,
            subsample: renderParams.subsample
          })}
          styles={ customSelectStyle }/>
      </div>
      <div className="form-group">
        <label>Subsampling</label>
        <Select options={subsampleOptions}
          value={{ label: renderParams.subsample == '' ? 'All Cells' : renderParams.subsample,
                   value: renderParams.subsample }}
          onChange={subsample => setRenderParams({
            userUpdated: true,
            annotation: renderParams.annotation,
            cluster: renderParams.cluster,
            subsample: subsample.value
          })}
          styles={customSelectStyle}/>
      </div>
      { setCollapseBy &&
        <div className="form-group">
          <label>Collapse by</label>
          <Select options={collapseOptions}
            value={_find(collapseOptions, {value: collapseBy})}
            onChange={ option => setCollapseBy(option.value) }
            styles={customSelectStyle}/>
        </div>
      }
    </div>
  )
}
