import React from 'react'

import Select from '~/lib/InstrumentedSelect'
import { clusterSelectStyle } from '~/lib/cluster-utils'

/** takes the server response and returns cluster options suitable for react-select */
function getSpatialOptions(allSpatialGroups) {
  const clusterList = allSpatialGroups ? allSpatialGroups : []
  return clusterList.map(group => {return { label: group.name, value: group.name }})
}

/**  */
function InlineClearButton() {
  return (
    <button className="clear-warning-inline">
      <svg height="14" width="14" viewBox="0 0 20 20">
        <path d="M14.348 14.849c-0.469 0.469-1.229 0.469-1.697 0l-2.651-3.030-2.651 3.029c-0.469 0.469-1.229 0.469-1.697 0-0.469-0.469-0.469-1.229 0-1.697l2.758-3.15-2.759-3.152c-0.469-0.469-0.469-1.228 0-1.697s1.228-0.469 1.697 0l2.652 3.031 2.651-3.031c0.469-0.469 1.228-0.469 1.697 0s0.469 1.229 0 1.697l-2.758 3.152 2.758 3.15c0.469 0.469 0.469 1.229 0 1.698z">
        </path>
      </svg>
    </button>
  )
}

/**
 * Determine whether to warn user about too many spatial groups
 *
 * Browsers usually limit the number of active WebGL contexts.  The limit
 * is often variable, and browser signaling of when the limit is exceeded is not
 * reliable.  So this uses a heuristic to assess when there are likely > 6
 * WebGL contexts, and if SCP should warn user of the potential issue.
 */
function getShouldWarn(spatialGroups, genes) {
  const numGenes = genes.length
  const numSpatial = spatialGroups.length
  return (
    (numGenes === 0 && numSpatial > 5) ||
    (numGenes === 1 && numSpatial > 2) ||
    (numGenes > 2 && numSpatial > 5)
  )
}

/** Component for displaying a spatial group selector
  @param spatialGroups: an array string names of the currently selected spatial groups
  @param updateSpatialGroups: an update function for handling changes to spatialGroups
  @param allSpatialGroups: an array of all possible spatial groups, each with a 'name' property
*/
export default function SpatialSelector({ spatialGroups, updateSpatialGroups, allSpatialGroups, genes }) {
  const options = getSpatialOptions(allSpatialGroups)
  const shouldWarn = getShouldWarn(spatialGroups, genes)
  return (
    <div className="form-group">
      <label className="labeled-select">Spatial groups
        <Select options={options}
          data-analytics-name="spatial-cluster-select"
          value={spatialGroups.map(name => ({ label: name, value: name }))}
          onChange={selectedOpts => updateSpatialGroups(
            selectedOpts ? selectedOpts.map(opt => opt.value) : []
          )}
          isMulti={true}
          isClearable={false}
          styles={clusterSelectStyle}/>
      </label>
      {shouldWarn &&
        <span className="warning-inline">Remove groups to avoid plot limit.<InlineClearButton/></span>
      }
    </div>
  )
}
