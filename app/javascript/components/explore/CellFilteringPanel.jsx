
import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faArrowLeft, faInfoCircle
} from '@fortawesome/free-solid-svg-icons'

import Select from '~/lib/InstrumentedSelect'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { annotationKeyProperties, clusterSelectStyle } from '~/lib/cluster-utils'
import { faChevronDown, faChevronRight } from '@fortawesome/free-solid-svg-icons'

import { initCellFaceting } from '~/lib/cell-faceting'
import { getSelectedClusterAndAnnot } from '~/components/explore/ExploreDisplayTabs'

/** Top content for cell facet filtering panel shown at right in Explore tab */
export function CellFilteringPanelHeader({
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

/**
 * Very brief notes on terms in SCP metadata convention, derived from:
 * https://singlecell.zendesk.com/hc/en-us/articles/360060609852-Required-Metadata
 */
const conventionalMetadataGlossary = {
  'biosample_id': 'Unique identifier for each sample in the study',
  'donor_id': 'Unique identifier for each biosample donor in the study',
  'species__ontology_label': 'Taxon name, from NCBITaxon',
  'disease__ontology_label': 'Disease name, from Mondo or PATO',
  'organ__ontology_label': 'Organ name, from Uberon',
  'library_preparation_protocol__ontology_label': 'From EFO',
  'sex': 'One of "female", "male", "mixed", or "unknown"',
  'cell_type__ontology_label': 'From Cell Ontology',
  'ethnicity__ontology_label': 'From Human Ancestry Ontology'
}

/** Determine if annotation is conventional from its raw name */
function getIsConventionalAnnotation(rawName) {
  return (
    rawName.includes('__ontology_label') ||
    ['donor_id', 'biosample_id'].includes(rawName)
  )
}

/** Convert e.g. "cell_type__ontology_label" to "Cell type" */
function parseAnnotationName(annotationIdentifier) {
  const rawName = annotationIdentifier.split('--')[0]
  const sansOntologyName = rawName.replace('__ontology_label', '')
  const sentenceCased = sansOntologyName[0].toUpperCase() + sansOntologyName.slice(1)
  const spaced = sentenceCased.replace(/_/g, ' ')
  let upId = spaced
  if (spaced.slice(-3) === ' id') {
    // e.g. Donor id -> Donor ID
    upId = upId.slice(0, -3) + upId.slice(-3).toUpperCase()
  }
  const displayName = upId
  return [displayName, rawName]
}

/** Toggle icon for collapsing a list; for each filter list, and all filter lists */
function CollapseToggleChevron({ isCollapsed, whatToToggle }) {
  let toggleIcon
  let toggleIconTooltipText
  if (!isCollapsed) {
    toggleIcon = <FontAwesomeIcon icon={faChevronDown} />
    toggleIconTooltipText = `Hide ${whatToToggle}`
  } else {
    toggleIcon = <FontAwesomeIcon icon={faChevronRight} />
    toggleIconTooltipText = `Show ${whatToToggle}`
  }

  return (
    <span
      className="facet-toggle-chevron"
      data-toggle="tooltip"
      data-original-title={toggleIconTooltipText}
      style={{ marginLeft: '20px', cursor: 'pointer' }}
    >
      {toggleIcon}
    </span>
  )
}

/** determine if the filter is checked or not */
function isChecked(annotation, item, checkedMap) {
  return checkedMap[annotation]?.includes(item)
}

/** Facet name and collapsible list of filter checkboxes */
function CellFacet({
  facet,
  checkedMap, handleCheck, updateFilteredCells,
  isAllListsCollapsed
}) {
  if (Object.keys(facet).length === 0) {
    // Only create the list if the facet exists
    return <></>
  }

  let defaultIsFullyCollapsed = false
  if (isAllListsCollapsed) {
    defaultIsFullyCollapsed = true
  }

  const [isPartlyCollapsed, setIsPartlyCollapsed] = useState(true)
  const [isFullyCollapsed, setIsFullyCollapsed] = useState(defaultIsFullyCollapsed)

  // Naturally sort groups (see https://en.wikipedia.org/wiki/Natural_sort_order)
  const sortedFilters = facet.groups.sort((a, b) => {
    return a[0].localeCompare(b[0], 'en', { numeric: true, ignorePunctuation: true })
  })

  // Handle truncating filter lists to account for any full or partial collapse
  let shownFilters = sortedFilters
  const numFiltersPartlyCollapsed = 5
  if (isPartlyCollapsed) {
    shownFilters = sortedFilters.slice(0, numFiltersPartlyCollapsed)
  }
  if (isFullyCollapsed) {
    shownFilters = []
  }

  useEffect(() => {
    setIsFullyCollapsed(isAllListsCollapsed)
  }, [isAllListsCollapsed])

  return (
    <div className="cell-facet" key={facet.annotation}>
      <FacetHeader
        facet={facet}
        isFullyCollapsed={isFullyCollapsed}
        setIsFullyCollapsed={setIsFullyCollapsed}
      />
      {shownFilters.map((item, i) => (
        <div style={{ marginLeft: '5px', lineHeight: '18px' }} key={i}>
          <label className="cell-filter-label">
            <input
              type="checkbox"
              checked={isChecked(facet.annotation, item, checkedMap)}
              value={item}
              data-analytics-name={`${facet.annotation}:${item}`}
              name={`${facet.annotation}:${item}`}
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
      {!isFullyCollapsed && sortedFilters.length > numFiltersPartlyCollapsed &&
        <a
          className="facet-toggle"
          style={{ 'fontSize': '13px' }}
          onClick={() => {setIsPartlyCollapsed(!isPartlyCollapsed)}}
        >
          {isPartlyCollapsed ? 'More...' : 'Less...'}
        </a>
      }
    </div>
  )
}

/** Get stylized name of facet, optional tooltip, collapse controls */
function FacetHeader({ facet, isFullyCollapsed, setIsFullyCollapsed }) {
  const [facetName, rawFacetName] = parseAnnotationName(facet.annotation)
  const isConventional = getIsConventionalAnnotation(rawFacetName)

  const facetNameStyle = {
    fontWeight: 'bold',
    marginTop: '12px', marginBottom: '1px',
    display: 'inline-block',
    width: 'fit-content'
  }

  let title = 'Author annotation'
  const tooltipAttrs = { 'data-toggle': 'tooltip' }
  if (isConventional) {
    title = 'SCP metadata convention annotation'
    const note = conventionalMetadataGlossary[rawFacetName]
    if (note) {
      title += `.  ${note}`
    }
  }
  title += `.  Name in data: ${rawFacetName}`
  tooltipAttrs['data-original-title'] = title

  const toggleClass = `cell-filters-${isFullyCollapsed ? 'hidden' : 'shown'}`

  return (
    <div
      className={`cell-facet-header ${toggleClass}`}
      onClick={() => {setIsFullyCollapsed(!isFullyCollapsed)}}
    >
      <span style={facetNameStyle} {...tooltipAttrs}>
        {facetName}
      </span>
      <CollapseToggleChevron
        isCollapsed={isFullyCollapsed}
        whatToToggle="filter list"
      />
    </div>
  )
}

/** Content for cell facet filter panel shown at right in Explore tab */
export function CellFilteringPanel({
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
  const [isAllListsCollapsed, setIsAllListsCollapsed] = useState(false)

  /** used to populate the checkedMap for the initial facets shown */
  function populateCheckedMap() {
    const tempCheckedMap = {}

    const numFacets = initialFiveFacets.length
    for (let i = 0; i < numFacets; i++) {
      tempCheckedMap[initialFiveFacets[i].annotation] = initialFiveFacets[i].groups
    }

    setCheckedMap(tempCheckedMap)

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

  /** Top header for the "Filter" section, including all-facet controls */
  function FilterSectionHeader({ isAllListsCollapsed, setIsAllListsCollapsed }) {
    return (
      <div
        className="filter-section-header"
        onClick={() => {setIsAllListsCollapsed(!isAllListsCollapsed)}}
      >
        <span
          style={{ 'fontWeight': 'bold' }}
          data-toggle="tooltip"
          data-original-title="Use checkboxes to show or hide cells in plots.  Deselected values are
        assigned to the '--Filtered--' group. Hover over this legend entry to highlight."
        >Filters</span>
        <CollapseToggleChevron
          isCollapsed={isAllListsCollapsed}
          setIsCollapsed={setIsAllListsCollapsed}
          whatToToggle="all filter lists"
        />
      </div>
    )
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
        <label className="labeled-select">
          <span
            className="cell-filtering-color-by"
            data-toggle="tooltip"
            data-original-title="Select the facet that the plot is colored by."
          >
          Color by
          </span>
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
            }}
            styles={clusterSelectStyle}/>
        </label>
        { Object.keys(checkedMap).length !== 0 &&
        <div style={{ marginTop: '10px', height: '450px', overflowY: 'scroll' }}>
          <FilterSectionHeader
            isAllListsCollapsed={isAllListsCollapsed}
            setIsAllListsCollapsed={setIsAllListsCollapsed}
          />
          <div style={{ margin: '2px', padding: '2px' }}>
            { shownFacets.map(facet => {
              return (
                <CellFacet
                  facet={facet}
                  checkedMap={checkedMap}
                  handleCheck={handleCheck}
                  updateFilteredCells={updateFilteredCells}
                  isAllListsCollapsed={isAllListsCollapsed}
                />
              )
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
