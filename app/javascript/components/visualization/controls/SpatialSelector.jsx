import React from 'react'

import Select from '~/lib/InstrumentedSelect'
import { clusterSelectStyle } from '~/lib/cluster-utils'

/** takes the server response and returns cluster options suitable for react-select */
function getSpatialOptions(allSpatialGroups) {
  const clusterList = allSpatialGroups ? allSpatialGroups : []
  return clusterList.map(group => {return { label: group.name, value: group.name }})
}

/** component for displaying a spatial group selector
  @param spatialGroups: an array string names of the currently selected spatial groups
  @param updateSpatialGroups: an update function for handling changes to spatialGroups
  @param allSpatialGroups: an array of all possible spatial groups, each with a 'name' property
*/
export default function SpatialSelector({ spatialGroups, updateSpatialGroups, allSpatialGroups }) {
  const options = getSpatialOptions(allSpatialGroups)
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
    </div>
  )
}
