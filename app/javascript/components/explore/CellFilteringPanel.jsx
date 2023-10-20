
import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faArrowLeft, faChevronDown, faChevronRight } from '@fortawesome/free-solid-svg-icons'

import Select from '~/lib/InstrumentedSelect'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { annotationKeyProperties, clusterSelectStyle } from '~/lib/cluster-utils'

/** Top content for cell facet filtering panel shown at right in Explore tab */
export function CellFilteringPanelHeader({
  togglePanel, updateFilteredCells
}) {
  return (
    <>
      <span> Filter plotted cells </span>
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
  let ynLess = upId
  if (upId.slice('-3').toUpperCase() === ' YN') {
    ynLess = ynLess.slice(0, -3)
  }
  const displayName = ynLess
  return [displayName, rawName]
}

/** Toggle icon for collapsing a list; for each filter list, and all filter lists */
function CollapseToggleChevron({ isCollapsed, whatToToggle, isLoaded }) {
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
    <span style={{ float: 'right', marginRight: '5px' }}>
      {!isLoaded &&
      <span
        data-toggle="tooltip"
        data-original-title="Loading data..."
        style={{ position: 'relative', top: '-5px', left: '-20px', cursor: 'default' }}
      >
        <LoadingSpinner height='14px'/>
      </span>
      }
      <span
        className="facet-toggle-chevron"
        data-toggle="tooltip"
        data-original-title={toggleIconTooltipText}
      >
        {toggleIcon}
      </span>
    </span>
  )
}

/** determine if the filter is checked or not */
function isChecked(annotation, item, checkedMap) {
  return checkedMap[annotation]?.includes(item)
}


/** Cell filter component */
function CellFilter({
  facet, filter, isChecked, checkedMap, handleCheck
}) {
  let facetLabelStyle = {}
  const inputStyle = { 'margin': '1px 5px 0 0', 'verticalAlign': 'top' }
  if (!facet.isLoaded) {
    inputStyle.cursor = 'default'
    facetLabelStyle = { color: '#777', cursor: 'default' }
  }

  return (
    <label className="cell-filter-label">
      <div style={{ marginLeft: '2px', lineHeight: '14px', ...facetLabelStyle }}>
        <input
          type="checkbox"
          checked={isChecked(facet.annotation, filter, checkedMap)}
          value={filter}
          data-analytics-name={`${facet.annotation}:${filter}`}
          name={`${facet.annotation}:${filter}`}
          onChange={event => {
            handleCheck(event)
          }}
          style={inputStyle}
          disabled={!facet.isLoaded}
        />
        <span className="cell-filter-label-text">{filter}</span>
        <span className="cell-filter-count">
          {facet.filterCounts && facet.filterCounts[filter]}
        </span>
      </div>
    </label>
  )
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

  const filters = facet.groups

  // TODO: Uncommenting below and replacing `filters` with `sortedFilters` in
  // this function makes the _filter list_ naturally sorted, but subtly
  // (and severely) causes a mismatch between the selected filter label and the
  // group of plotted cells that actually gets hidden in the plot.
  //
  // Naturally sort groups (see https://en.wikipedia.org/wiki/Natural_sort_order)
  // const sortedFilters = facet.groups.sort((a, b) => {
  //   return a[0].localeCompare(b[0], 'en', { numeric: true, ignorePunctuation: true })
  // })

  // Handle truncating filter lists to account for any full or partial collapse
  let shownFilters = filters
  const numFiltersPartlyCollapsed = 5
  if (isPartlyCollapsed) {
    shownFilters = filters.slice(0, numFiltersPartlyCollapsed)
  }
  if (isFullyCollapsed) {
    shownFilters = []
  }

  useEffect(() => {
    setIsFullyCollapsed(isAllListsCollapsed)
  }, [isAllListsCollapsed])

  let facetStyle = {}
  if (!facet.isLoaded) {
    facetStyle = {
      color: '#777',
      cursor: 'default'
    }
  }

  return (
    <div
      className="cell-facet"
      key={facet.annotation}
      style={facetStyle}
    >
      <FacetHeader
        facet={facet}
        isFullyCollapsed={isFullyCollapsed}
        setIsFullyCollapsed={setIsFullyCollapsed}
      />
      {shownFilters.map((filter, i) => {
        return (
          <CellFilter
            facet={facet}
            filter={filter}
            isChecked={isChecked}
            checkedMap={checkedMap}
            handleCheck={handleCheck}
            updateFilteredCells={updateFilteredCells}
            key={i}
          />
        )
      })
      }
      {!isFullyCollapsed && filters.length > numFiltersPartlyCollapsed &&
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
    marginBottom: '1px',
    display: 'inline-block',
    width: 'calc(100% - 30px)'
  }
  const tooltipableFacetNameStyle = {
    width: 'content-fit'
  }
  if (!facet.isLoaded) {
    facetNameStyle.color = '#777'
    facetNameStyle.cursor = 'default'
  }

  let title = 'Author annotation'
  const tooltipAttrs = { 'data-toggle': 'tooltip' }
  if (isConventional) {
    title = 'Conventional annotation'
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
      <span style={facetNameStyle}>
        <span style={tooltipableFacetNameStyle} {...tooltipAttrs}>
          {facetName}
        </span>
      </span>
      <CollapseToggleChevron
        isCollapsed={isFullyCollapsed}
        whatToToggle="filter list"
        isLoaded={facet.isLoaded}
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
  cellFilteringSelection,
  cellFilterCounts,
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

  const facets = cellFaceting.facets.map(facet => {
    facet.filterCounts = cellFilterCounts[facet.annotation]
    return facet
  })
  const [checkedMap, setCheckedMap] = useState(cellFilteringSelection)
  const [colorByFacet, setColorByFacet] = useState(shownAnnotation)
  const shownFacets = facets
  const [isAllListsCollapsed, setIsAllListsCollapsed] = useState(false)

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
        >Filter by</span>
        <CollapseToggleChevron
          isCollapsed={isAllListsCollapsed}
          setIsCollapsed={setIsAllListsCollapsed}
          whatToToggle="all filter lists"
          isLoaded={true}
        />
      </div>
    )
  }

  /** Add or remove checked item from list */
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

  const verticalPad = 295 // Accounts for all UI real estate above table header

  const filterSectionHeight = window.innerHeight - verticalPad
  const filterSectionHeightProp = `${filterSectionHeight}px`

  return (
    <>
      <div>
        <label className="labeled-select">
          <span
            className="cell-filtering-color-by"
            data-toggle="tooltip"
            data-original-title="Color the plot by an annotation"
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
        <>
          <div style={{ marginTop: '10px' }}>
            <FilterSectionHeader
              isAllListsCollapsed={isAllListsCollapsed}
              setIsAllListsCollapsed={setIsAllListsCollapsed}
            />
            <div className="cell-facet-list" style={{ height: filterSectionHeightProp, overflowY: 'scroll' }}>
              { shownFacets.map((facet, i) => {
                return (
                  <CellFacet
                    facet={facet}
                    checkedMap={checkedMap}
                    handleCheck={handleCheck}
                    updateFilteredCells={updateFilteredCells}
                    isAllListsCollapsed={isAllListsCollapsed}
                    key={i}
                  />
                )
              })}
            </div>
          </div>
        </>
        }
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
