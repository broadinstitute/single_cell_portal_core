import React from 'react'

import Select from '~/lib/InstrumentedSelect'
import { getAnnotationValues, clusterSelectStyle, naturalSort } from '~/lib/cluster-utils'

/**
 * Get annotation labels that have > 1 cell in the labeled group, if possible
 */
function getEligibleLabels(exploreParamsWithDefaults, exploreInfo) {
  const rawAnnotLabels = getAnnotationValues(
    exploreParamsWithDefaults?.annotation,
    exploreInfo?.annotationList
  )
  let annotationLabels = naturalSort(rawAnnotLabels)

  /** TODO (SCP-5760): Propagate these window.SCP values via React */
  const countsByLabel = window.SCP.countsByLabel
  if (
    countsByLabel &&
    annotationLabels.includes(countsByLabel[0])
  ) {
    annotationLabels = annotationLabels.filter(label => countsByLabel[label] > 0)
  }

  return annotationLabels
}

/** Get default option for label drop-down menu */
function getShownOption(options, exploreParamsWithDefaults) {
  let shownOption = options.find(o => o.value === exploreParamsWithDefaults.label)
  if (!shownOption) {
    shownOption = options[0]
  }
  return shownOption
}

/**
  Renders a label selector
  */
export default function LabelControl({
  exploreParamsWithDefaults,
  exploreInfo,
  updateClusterParams
}) {
  const labels = getEligibleLabels(exploreParamsWithDefaults, exploreInfo)

  const options = labels.map(label => {return { label, value: label }})

  const shownOption = getShownOption(options, exploreParamsWithDefaults)

  return (
    <div className="form-group">
      <label className="labeled-select">Color by expression in&nbsp;
        <Select
          options={options}
          data-analytics-name="label-select"
          value={shownOption}
          onChange={newOption => {
            updateClusterParams({ label: newOption.label })
          }}
          styles={clusterSelectStyle}/>
      </label>
    </div>
  )
}
