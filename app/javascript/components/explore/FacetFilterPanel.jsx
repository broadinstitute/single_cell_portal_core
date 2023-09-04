
import React, { useState, useEffect, useRef } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faArrowLeft, faSearch, faTimes, faAngleUp, faAngleDown, faUndo, faBullseye, faInfoCircle, faPlus
} from '@fortawesome/free-solid-svg-icons'

import Button from 'react-bootstrap/lib/Button'
import Select from '~/lib/InstrumentedSelect'
import { annotationKeyProperties, clusterSelectStyle } from '~/lib/cluster-utils'
import { v4 as uuidv4 } from 'uuid'

/** Return selected annotation object, including its `values` a.k.a. groups */
function getAnnotationObject(exploreParamsWithDefaults, exploreInfo) {
  const selectedAnnotation = exploreParamsWithDefaults?.annotation
  return exploreInfo.annotationList.annotations.find(thisAnnotation => {
    return (
      thisAnnotation.name === selectedAnnotation.name &&
      thisAnnotation.type === selectedAnnotation.type &&
      thisAnnotation.scope === selectedAnnotation.scope
    )
  })
}

/** Top matter for cell facet filtering panel shown at right in Explore tab */
export function FacetFilterPanelHeader({
  togglePanel, updateFilteredCells
}) {
  return (
    <>
      <span>Cell facet filtering </span>
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
  updateFilteredCells
}) {
  // initialFivefacets
  const [initialFivefacets, setInitialFiveFacets] = useState(cellFaceting?.facets)
  const [checkedMap, setCheckedMap] = useState({})


  const [colorByFacet, setColorByFacet] = useState(shownAnnotation)

  // Add/Remove checked item from list
  const handleCheck = event => {
    const facetName = event.target.name.split(':')[0]
    const fullFacetName = event.target.name
    console.log('event.target.name:', event.target.name)

    // {faceName: [checkedGroup, checkedGroup], faceName: []}
    console.log('checkedMap[facetName]:', checkedMap[facetName])
    let updatedList = checkedMap[facetName] ? [...checkedMap[facetName]] : []

    console.log('event.target.checked:', event.target.checked)

    if (event.target.checked) {
      updatedList = [...updatedList, event.target.value]
    } else {
      console.log('updatedlist in else:', updatedList)
      updatedList.splice(updatedList.indexOf(event.target.value), 1)
    }
    checkedMap[facetName] = updatedList

    // facetName
    setCheckedMap(checkedMap)
    // updateFilteredCells()
    console.log('checkedMap:', checkedMap)
    updateFilteredCells(checkedMap)
  }

  // // Generate string of checked items
  // const checkedItems = checked.length ?
  //   checked.reduce((total, item) => {
  //     return `${total }, ${ item}`
  //   }) :
  //   ''

  const isChecked = item =>
  checkedMap.values?.includes(item) ? 'checked-item' : 'not-checked-item'

  // const listData = cellFaceting.facets[0].groups[0].map(group => {return { id: group, value: group }})

  const currentlyInUseAnnotations = { 'colorby:': '', 'facets': [] }
  const annotationOptions = getAnnotationOptions(annotationList, cluster)


  /** hjh*/
  const createFacetFilterCheckList = singleCellFaceting => {
    // limit the number of groups shown by default t the first 10
    const firstTenGroups = singleCellFaceting.groups.slice(0, 3)
    console.log('firsttem:', firstTenGroups)
    console.log('singleCellFaceting.groups:', singleCellFaceting.groups)


    // button to show more
    // button to show none
    // if nutton false then firstTenGroups.map() else do all.map

    return <div >
      <label>{singleCellFaceting.annotation}</label>
      {firstTenGroups.length === singleCellFaceting.groups.length && <>
        {singleCellFaceting.groups.map((item, index) => (
          <div key={index}>
            <input value={item} type="checkbox" name={`${singleCellFaceting.annotation}:${item}`} onChange={handleCheck} />
            <span className={isChecked(item)}>{item}</span>
          </div>
        ))}
        <div> Show more.. </div> </>
      }
      {firstTenGroups.length !== singleCellFaceting.groups.length && firstTenGroups.map((item, index) => (
        <div key={index}>
          <input value={item} type="checkbox" name={`${singleCellFaceting.annotation}:${item}`} onChange={handleCheck} />
          <span className={isChecked(item)}>{item}</span>
        </div>
      ))}
    </div>
  }

  return (
    <>
      <div className="form-group">
        <button
          onClick={
            () => createFacetFilterCheckList(initialFivefacets[0])}>
          Add facet
          <FontAwesomeIcon icon={faPlus}/> &nbsp;
        </button>
        <label className="labeled-select">Color by:&nbsp;
          <a className="action help-icon"
            data-toggle="tooltip"
            data-original-title="Select how cells are colored">
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
              setCheckedMap({})
            }}
            styles={clusterSelectStyle}/>
        </label>


        {initialFivefacets &&

        <div >
          {createFacetFilterCheckList(initialFivefacets[1])}
          {createFacetFilterCheckList(initialFivefacets[2])}
          {createFacetFilterCheckList(initialFivefacets[3])}
        </div>}
      </div>
    </>
  )
}


/** takes the server response and returns annotation options suitable for react-select */
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

/** */
export function createFacetFilterCheckList({
  singleCellFaceting, isChecked
}) {
  const [open, setOpen] = useState(true)

  const toggle = () => {
    setOpen(!open)
  };
  // limit the number of groups shown by default t the first 10
  const firstTenGroups = singleCellFaceting.groups.slice(0, 3)
  const restOfGroups = singleCellFaceting.groups.slice(0, 3)
  console.log('firsttem:', firstTenGroups)
  console.log('singleCellFaceting.groups:', singleCellFaceting.groups)


  // button to show more
  // button to show none
  // if nutton false then firstTenGroups.map() else do all.map

  return <div >
    <label>{singleCellFaceting.annotation}</label>
    {firstTenGroups.length === singleCellFaceting.groups.length && <>
      {firstTenGroups.map((item, index) => (
        <div key={index}>
          <input value={item} type="checkbox" name={`${singleCellFaceting.annotation}:${item}`} onChange={handleCheck} />
          <span className={isChecked(item)}>{item}</span>
        </div>
      ))}
      <button onClick={toggle}> Show more.. </button> 
      {open && restOfGroups.map((item, index) => (
        <div key={index}>
          <input value={item} type="checkbox" name={`${singleCellFaceting.annotation}:${item}`} onChange={handleCheck} />
          <span className={isChecked(item)}>{item}</span>
        </div>
      )) }</>
    }
    {singleCellFaceting.groups.length !== singleCellFaceting.groups.length && singleCellFaceting.groups.map((item, index) => (
      <div key={index}>
        <input value={item} type="checkbox" name={`${singleCellFaceting.annotation}:${item}`} onChange={handleCheck} />
        <span className={isChecked(item)}>{item}</span>
      </div>
    ))}
  </div>
}


