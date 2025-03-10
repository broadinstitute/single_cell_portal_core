import React from 'react'

import Select from '~/lib/InstrumentedSelect'
import { getAnnotationValues, clusterSelectStyle } from '~/lib/cluster-utils'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faInfoCircle } from '@fortawesome/free-solid-svg-icons'

// /** Get dropdown menu of annotation labels; pick one to color genes */
// function writePathwayAnnotationLabelMenu(labels, pathwayGenes, dotPlotMetrics) {
//   const options = labels.map(label => `<option>${label}</option>`)
//   const menu =
//     `<span class="pathway-label-menu-container" style="margin-left: 10px;">` +
//       `<label>Expression in:</label> <select class="pathway-label-menu">${options.join()}</select>` +
//     `</span>`
//   const headerLink = document.querySelector('._ideoPathwayHeader a')
//   document.querySelector('.pathway-label-menu-container')?.remove()
//   headerLink.insertAdjacentHTML('afterend', menu)
//   const menuSelectDom = document.querySelector('.pathway-label-menu')
//   menuSelectDom.addEventListener('change', () => {
//     const newLabel = menuSelectDom.value
//     colorPathwayGenesByExpression(pathwayGenes, dotPlotMetrics, newLabel)
//   })
// }

/**
 * Get annotation labels that have > 1 cell in the labeled group, if possible
 */
function getEligibleLabels(exploreParamsWithDefaults, exploreInfo) {
  const rawAnnotLabels = getAnnotationValues(
    exploreParamsWithDefaults?.annotation,
    exploreInfo?.annotationList
  )

  let annotationLabels = rawAnnotLabels

  /** TODO (SCP-5760): Propagate these window.SCP values via React */
  const countsByLabel = window.SCP.countsByLabel
  if (countsByLabel) {
    annotationLabels = annotationLabels.filter(label => countsByLabel[label] > 0)
  }

  return annotationLabels
}


/**
  Renders a label selector
  */
export default function LabelControl({
  exploreParamsWithDefaults,
  exploreInfo,
  updateExploreParams
}) {
  const labels = getEligibleLabels(exploreParamsWithDefaults, exploreInfo)
  const shownLabel = labels[0]

  const options = labels.map(label => {return { label, value: label }})

  return (
    <div className="form-group">
      <label className="labeled-select">Label&nbsp;
        <a className="action help-icon"
          data-toggle="tooltip"
          data-original-title="Select how cells are colored">
          <FontAwesomeIcon icon={faInfoCircle}/>
        </a>
        <Select
          options={options}
          data-analytics-name="label-select"
          value={options[0]}
          onChange={newLabel => {
            // setShownLabel(newLabel)
            updateExploreParams({ label: newLabel })}
          }
          styles={clusterSelectStyle}/>
      </label>
    </div>
  )
}
