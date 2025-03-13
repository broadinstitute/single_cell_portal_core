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
  if (countsByLabel) {
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
  // updatePathwayExpression
}) {
  const labels = getEligibleLabels(exploreParamsWithDefaults, exploreInfo)
  console.log('in LabelControl, labels', labels)

  const options = labels.map(label => {return { label, value: label }})

  console.log('in LabelSelector, exploreParamsWithDefaults.label', exploreParamsWithDefaults.label)
  const shownOption = getShownOption(options, exploreParamsWithDefaults)

  console.log('in LabelSelector, shownOption', shownOption)

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
