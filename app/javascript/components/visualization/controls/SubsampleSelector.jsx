import React from 'react'
import { faInfoCircle } from '@fortawesome/free-solid-svg-icons'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { Popover, OverlayTrigger } from 'react-bootstrap'

import { clusterSelectStyle } from '~/lib/cluster-utils'
import Select from '~/lib/InstrumentedSelect'


/** takes the server response and returns subsample options suitable for react-select
 * Setting isPerfTest to true will render a large array of options, regardless of the study content, so
 * meant to be used in conjunction with ClustersController::generate_fixed_size_plot_data
 */
function getSubsampleOptions(annotationList, clusterName) {
  let subsampleOptions = []
  if (clusterName && annotationList.subsample_thresholds) {
    let clusterSubsamples = annotationList.subsample_thresholds[clusterName]
    if (!clusterSubsamples) {
      clusterSubsamples = []
    }
    subsampleOptions = subsampleOptions.concat(
      clusterSubsamples
        .filter(num => num >= 100000)
        .map(num => {
        // convert everything to strings to make the comparisons easier
          return { label: `${num}`, value: `${num}` }
        })
    )
  }
  subsampleOptions.push({ label: 'All Cells', value: 'all' })
  return subsampleOptions
}


/**
  Renders a subsample selector.
    @param annotationList: the results of a call to scpApi/fetchClusterOptions (or equivalent).
    @param cluster: the name of the cluster selected
    @param subsample: the current subsample selected
    @param updateClusterParams: update function that accepts changes to cluster, annotation, and/or subsample properties
  */
export default function SubsampleSelector({
  annotationList,
  cluster,
  subsample,
  updateClusterParams
}) {
  if (!annotationList) {
    annotationList = { default_cluster: null, default_annotation: null, annotations: [] }
  }

  const subsampleOptions = getSubsampleOptions(annotationList, cluster)

  const hasUsefulThreshold = subsampleOptions.find(option => option.value === '100000')

  if (!hasUsefulThreshold) {
    return <></>
  }

  return (
    <div className="form-group">
      <label className="labeled-select"> Subsampling&nbsp;
        <OverlayTrigger delayHide={1500} rootClose placement="top" overlay={subsamplingPopover}>
          <FontAwesomeIcon data-analytics-name="subsampling-help-icon"
            className="action log-click help-icon" icon={faInfoCircle}/>
        </OverlayTrigger>
      </label>
      <Select options={subsampleOptions}
        data-analytics-name="subsample-select"
        value={{
          label: subsample == 'all' ? 'All Cells' : `${subsample}`,
          value: `${subsample}`
        }}
        onChange={newSubsample => updateClusterParams({
          subsample: newSubsample.value
        })}
        styles={clusterSelectStyle}/>

    </div>
  )
}

const subsamplingPopover = (
  <Popover id="explore-subsampling-helptext">
    Show a representative subsample of the current clusters
    (<a href='https://singlecell.zendesk.com/hc/en-us/articles/360060610032-Cluster-File-Subsampling'
      rel="noreferrer" target='_blank'>learn more</a>).
    <br/>
    <span className="detail">
      Choosing &quot;All cells&quot; may dramatically increase rendering time for studies with &gt;100K cells.
    </span>
  </Popover>
)
