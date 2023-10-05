
import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faArrowLeft, faInfoCircle
} from '@fortawesome/free-solid-svg-icons'

import Select from '~/lib/InstrumentedSelect'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { annotationKeyProperties, clusterSelectStyle } from '~/lib/cluster-utils'
import { initCellFaceting } from '~/lib/cell-faceting'
import { getSelectedClusterAndAnnot } from '~/components/explore/ExploreDisplayTabs'

/** Top content for cell facet filtering panel shown at right in Explore tab */
export function FacetFilterPanelHeader({
  togglePanel, updateFilteredCells
}) {
  return (
    <>
      <span> Cell filtering </span>
      <button className="action fa-lg cell-filtering-exit-panel"
        onClick={() => {
          updateFilteredCells(null)
          togglePanel('options')
        }}
        title="Back to options panel"
        data-analytics-name="cell-filtering-panel-exit">
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
  updateFilteredCells
}) {
  if (!cellFaceting) {
    const loadingTextStyle = { position: 'absolute', top: '50%', left: '30%' }
    return (
      <div>
        <LoadingSpinner className="fa-lg"/>
        <span style={loadingTextStyle}>Loading cell filters...</span>
      </div>
    )
  }

  const [initialFiveFacets, setinitialFiveFacets] = useState(cellFaceting?.facets)
  const [checkedMap, setCheckedMap] = useState({})
  const [colorByFacet, setColorByFacet] = useState(shownAnnotation)
  const [shownFacets, setShownFacets] = useState()
  const [options, setOptions] = useState()

  /** create the checklist for filtering the facet */
  function createFacetFilterCheckList(singleCellFaceting) {
    // only create the checklist if the facet exists
    if (Object.keys(singleCellFaceting).length !== 0
    ) {
      // grab the show facet names to filter the select options so there won't be duplicates
      const facetNames = shownFacets.map(facet => {return facet.annotation.split('--')[0]})
      const otherMenuOptions = options.filter(opt => !facetNames.includes(opt.label))
      return <div key={singleCellFaceting.annotation}>
        <div>
          <Select
            name={singleCellFaceting.annotation}
            options={otherMenuOptions}
            data-analytics-name="annotation-select"
            value={options.find(opt => opt.value.annotation === singleCellFaceting.annotation)}
            onChange={(newAnnotation, event) => {
              updateCheckedMap(newAnnotation, event)
            }}
          />
        </div>
        {singleCellFaceting.groups.map((item, index) => (
          <div style={{ marginLeft: '5px' }} key={index}>
            <label style={{ fontWeight: 'normal' }}>
              <input
                type="checkbox"
                checked={isChecked(singleCellFaceting.annotation, item)}
                value={item}
                name={`${singleCellFaceting.annotation}:${item}`}
                onChange={event => {
                  handleCheck(event)
                  updateFilteredCells(checkedMap)
                }}
                style={{ marginRight: '5px' }}
              />
              {item}
            </label>
          </div>
        ))}
      </div>
    }
  }

  /** used to populate the checkedMap for the initial facets shown */
  function populateCheckedMap() {
    const tempCheckedMap = {}

    // only initalize up to three facets for now
    const numFacets = initialFiveFacets.length > 2 ? 3 : initialFiveFacets.length
    for (let i = 0; i < numFacets; i++) {
      tempCheckedMap[initialFiveFacets[i].annotation] = initialFiveFacets[i].groups
    }

    setCheckedMap(tempCheckedMap)


    setOptions(initialFiveFacets.map(facet => {
      return { value: facet, label: facet.annotation.split('--')[0] }
    }))

    // set the shownFacets with the same facets as the checkedMap starts with
    setShownFacets(initialFiveFacets.slice(0, numFacets))
  }


  /** Update the checkedMap state that is used for setting up the filtering checkboxes */
  function updateCheckedMap(newSingleCellFaceting, event) {
    const tempCheckedMap = { ...checkedMap }
    // add the new facet to the tempCheckedMap
    tempCheckedMap[newSingleCellFaceting.value.annotation] = newSingleCellFaceting.value.groups

    // set the checkedMap state with the updated list
    setCheckedMap(tempCheckedMap)

    const tempShownFacets = [...shownFacets]

    // grab the index of the facet that is to be replaced
    const indexToRep = tempShownFacets.findIndex(facet => facet.annotation === event.name)

    // replace the existing facet with the new facet at the index determined above
    tempShownFacets[indexToRep] = {
      annotation: newSingleCellFaceting.value.annotation,
      groups: newSingleCellFaceting.value.groups
    }

    // set the facets that are shown in the UI
    setShownFacets(tempShownFacets)
  }


  /** Add/Remove checked item from list */
  function handleCheck(event) {
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
  function isChecked(annotation, item) {
    return checkedMap[annotation]?.includes(item)
  }

  const currentlyInUseAnnotations = { colorBy: '', facets: [] }
  const annotationOptions = getAnnotationOptions(annotationList, cluster)

  /** populate the checkedMap state if it's empty
   * (this is for initial setting upon page loading and the cellFaceting prop initializing) */
  useEffect(() => {
    if (Object.keys(checkedMap).length === 0) {
      populateCheckedMap()
    }
  }, [cellFaceting])

  return (
    <>
      <div className="form-group">
        <label className="labeled-select">Color by&nbsp;
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
              currentlyInUseAnnotations.colorBy = newColorByAnnotation
              updateFilteredCells(null)
            }}
            styles={clusterSelectStyle}/>
        </label>
        { Object.keys(checkedMap).length !== 0 &&
        <div style={{ 'marginTop': '5px' }}>
          <h5>Filter by&nbsp;
            <a className="action help-icon"
              data-toggle="tooltip"
              data-original-title="Use the checkboxes to filter points from the plot.  Deselected values are
                assigned to the '--Filtered--' group. Hover over this legend entry to highlight."
            >
              <FontAwesomeIcon icon={faInfoCircle}/>
            </a></h5>
          <div style={{ margin: '2px', padding: '2px' }}>
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
