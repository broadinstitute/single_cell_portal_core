
import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faArrowLeft, faInfoCircle
} from '@fortawesome/free-solid-svg-icons'

import Select from '~/lib/InstrumentedSelect'
import { annotationKeyProperties, clusterSelectStyle } from '~/lib/cluster-utils'
import { initCellFaceting } from '~/lib/cell-faceting'
import { getSelectedClusterAndAnnot } from '~/components/explore/ExploreDisplayTabs'


/** Top content for cell facet filtering panel shown at right in Explore tab */
export function FacetFilterPanelHeader({
  togglePanel, updateFilteredCells
}) {
  return (
    <>
      <span> Cell facet filtering </span>
      <button className="action fa-lg de-exit-panel"
        onClick={() => {
          updateFilteredCells({})
          togglePanel('default')
        }}
        title="Exit cell facet filter panel"
        data-analytics-name="-facet-filter-panel-exit">
        <FontAwesomeIcon icon={faArrowLeft}/>
      </button>
    </>
  )
}

/** Content for cell facet filter panel shown at right in Explore tab */
export function FacetFilterPanel({
  annotationList,
  cluster,
  shownAnnotation,
  updateClusterParams,
  cellFaceting,
  updateFilteredCells,
  exploreParams,
  exploreInfo,
  setCellFaceting,
  studyAccession
}) {
  const [initialFivefacets, setInitialFiveFacets] = useState(cellFaceting?.facets)
  const [checkedMap, setCheckedMap] = useState({})
  const [colorByFacet, setColorByFacet] = useState(shownAnnotation)
  const [shownFacets, setShownFacets] = useState()
  const [options, setOptions] = useState()

  /** create the checklist for filtering the facet */
  const createFacetFilterCheckList = singleCellFaceting => {
    // only create the checklist if the facet exists
    if (Object.keys(singleCellFaceting).length !== 0
    ) {
      // grab the show facet names to filter the select options so there won't be duplicates
      const facetNames = shownFacets.map(facet => {return facet.annotation.split('--')[0]})
      return <div>
        <div>
          <Select
            name={singleCellFaceting.annotation}
            options={options.filter(opt => {return !facetNames.includes(opt.label)})}
            data-analytics-name="annotation-select"
            value={options.find(opt => opt.value.annotation === singleCellFaceting.annotation)}
            onChange={(newAnnotation, event) => {
              updateCheckedMap(newAnnotation, event)
            }}
          />
        </div>
        {singleCellFaceting.groups.map((item, index) => (
          <div key={index}>
            <input checked={
              isChecked(singleCellFaceting.annotation, item)}
            value={item}
            type="checkbox"
            name={`${singleCellFaceting.annotation}:${item}`}
            onChange={event => {
              handleCheck(event)
              // updateFilteredCells(checkedMap)
            }}/>
            <span style={{ marginLeft: '4px' }} >{item}</span>
          </div>
        ))}
      </div>
    }
  }

  /** used to populate the checkedMap for the initial facets shown */
  const populateCheckedMap = () => {
    const tempCheckedMap = {}

    // only initalize up to three facets for now
    const numFacets = initialFivefacets.length > 2 ? 3 : initialFivefacets.length
    for (let i = 0; i < numFacets; i++) {
      tempCheckedMap[initialFivefacets[i].annotation] = initialFivefacets[i].groups
    }

    setCheckedMap(tempCheckedMap)

    setOptions(initialFivefacets.map(facet => {
      return { value: facet, label: facet.annotation.split('--')[0] }
    }))

    // set the shownFacets with the same facets as the checkedMap starts with
    setShownFacets(initialFivefacets.slice(0, numFacets))
  }


  /** Update the checkedMap state that is used for setting up the filtering checkboxes */
  const updateCheckedMap = (newSingleCellFaceting, event) => {
    const tempCheckedMap = { ...checkedMap }
    // add the new facet to the tempCheckedMap
    tempCheckedMap[newSingleCellFaceting.value.annotation] = newSingleCellFaceting.value.groups

    // set the checkedMap state with the updated list
    setCheckedMap(tempCheckedMap)

    const tempShownFacets = [...shownFacets]

    // grab the index of the facet that is to be replaced
    const indexToRep = tempShownFacets.findIndex(facet => facet.annotation === event.name)

    // replace the existing facet with the new facet at the index determined above
    tempShownFacets[indexToRep] = { 'annotation': newSingleCellFaceting.value.annotation, 'groups': newSingleCellFaceting.value.groups }

    // set the facets that are shown in the UI
    setShownFacets(tempShownFacets)
  }


  // Add/Remove checked item from list
  const handleCheck = event => {
    // grab the name of the facet from the check event
    const facetName = event.target.name.split(':')[0]

    let updatedList = checkedMap[facetName] ? [...checkedMap[facetName]] : []

    // if the event was a check then add the checked filter to the list
    if (event.target.checked) {
      updatedList = [...updatedList, event.target.value]
    } else {
      // otherwise the event was an uncheck so remove the filter from the list
      updatedList = updatedList.filter(item => {
        return item !== event.target.value
      })
    }
    // update the checkedMap state with the filter in it's updated condition
    checkedMap[facetName] = updatedList
    setCheckedMap(checkedMap)

    // update the filtered cells based on the checked condition of the filters
    updateFilteredCells(checkedMap)
  }

  /** determine if the filter is checked or not */
  const isChecked = (annotation, item) => {
    return checkedMap[annotation]?.includes(item)
  }

  const currentlyInUseAnnotations = { 'colorby:': '', 'facets': [] }
  const annotationOptions = getAnnotationOptions(annotationList, cluster)


  /** populate the checkedMap state if it's empty
   * (this is for initial setting upon page loading and the cellFaceting prop initializing) */
  useEffect(() => {
    if (Object.keys(checkedMap).length === 0) {
      populateCheckedMap()
    }
  }, [cellFaceting])

  // if the exploreParams update need to reset the initial cell facets
  useEffect(() => {
    const [selectedCluster, selectedAnnot] = getSelectedClusterAndAnnot(exploreInfo, exploreParams)
    const allAnnots = exploreInfo?.annotationList.annotations
    if (allAnnots && allAnnots.length > 0) {
      initCellFaceting(
        selectedCluster, selectedAnnot, studyAccession, allAnnots
      )
        .then(newCellFaceting => {
          setCellFaceting(newCellFaceting)
        })
    }
  }, [exploreParams])


  return (
    <>
      <div className="form-group">
        <label className="labeled-select">Color plotted points by:&nbsp;
          <a className="action help-icon"
            data-toggle="tooltip"
            data-original-title="Select the facet that the plot is colored by.">
            <FontAwesomeIcon icon={faInfoCircle}/>
          </a>
          <Select
            options={annotationOptions}
            data-analytics-name="annotation-select"
            value={colorByFacet}
            isOptionDisabled={annotation => annotation.isDisabled}
            getOptionLabel={annotation => annotation.name}
            getOptionValue={annotation => annotation.scope + annotation.name + annotation.cluster_name}
            onChange={newColorByAnnotation => {
              setColorByFacet(newColorByAnnotation)
              updateClusterParams({ annotation: newColorByAnnotation })
              currentlyInUseAnnotations.colorby = newColorByAnnotation
              updateFilteredCells({})
            }}
            styles={clusterSelectStyle}/>
        </label>
        { Object.keys(checkedMap).length !== 0 &&
        <div style={{ 'marginTop': '5px' }}>
          <h5>Filter plotted points by: <a className="action help-icon"
            data-toggle="tooltip"
            data-original-title="Use the checkboxes to add and remove points from the plot.">
            <FontAwesomeIcon icon={faInfoCircle}/>
          </a></h5>
          <div style={{ border: '1px solid black', margin: '2px', padding: '2px' }}>
            { shownFacets.map(singleFacet => {
              return createFacetFilterCheckList(singleFacet)
            })}
          </div>
        </div>}
      </div>
    </>
  )
}

/** create the annotation options mapping to be used in selects*/
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
