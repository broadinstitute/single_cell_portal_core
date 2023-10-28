
import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faArrowLeft, faChevronDown, faChevronRight, faUndo } from '@fortawesome/free-solid-svg-icons'

import Select from '~/lib/InstrumentedSelect'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { annotationKeyProperties, clusterSelectStyle } from '~/lib/cluster-utils'

const tooltipAttrs = {
  'data-toggle': 'tooltip',
  'data-delay': '{"show": 150}' // Avoid flurry of tooltips on passing hover
}

/** Top content for cell facet filtering panel shown at right in Explore tab */
export function CellFilteringPanelHeader({
  togglePanel, updateFilteredCells
}) {
  return (
    <>
      <span>Filter plotted cells</span>
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
function FacetTools({
  isCollapsed, whatToToggle,
  isLoaded,
  isRoot=false, facets, checkedMap, handleResetFilters
}) {
  return (
    <span className="facet-tools">
      {!isLoaded &&
      <span
        {...tooltipAttrs}
        data-original-title="Loading data..."
        style={{ position: 'relative', top: '-5px', left: '-20px', cursor: 'default' }}
      >
        <LoadingSpinner height='14px'/>
      </span>
      }
      {isRoot &&
        <ResetFiltersButton
          facets={facets}
          checkedMap={checkedMap}
          handleResetFilters={handleResetFilters}
        />
      }
      <CollapseToggleChevron
        isCollapsed={isCollapsed}
        whatToToggle={whatToToggle}
      />
    </span>
  )
}

/** Button to reset all filters to their default, initial state */
function ResetFiltersButton({ facets, checkedMap, handleResetFilters }) {
  // Assess if filter-section-level checkbox should be indeterminate, i.e. "-",
  // which is a common state in hierarchical checkboxes to indicate that
  // some lower checkboxes are checked, and some are not.
  let numTotalFilters = 0
  facets.forEach(facet => numTotalFilters += facet.groups.length)
  let numCheckedFilters = 0
  Object.entries(checkedMap).forEach(([facet, filters]) => {
    numCheckedFilters += filters.length
  })
  const isResetEligible = numTotalFilters !== numCheckedFilters
  const resetDisplayClass = isResetEligible ? '' : 'hide-reset'

  return (
    <a
      onClick={() => handleResetFilters()}
      className={`reset-cell-filters ${resetDisplayClass}`}
      data-analytics-name="reset-cell-filters"
      data-toggle="tooltip"
      data-original-title="Reset filters"
    >
      <FontAwesomeIcon icon={faUndo}/>
    </a>
  )
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
      data-original-title={toggleIconTooltipText}
      {...tooltipAttrs}
    >
      {toggleIcon}
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
    <label className="cell-filter-label" style={{ marginLeft: '18px' }}>
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
  checkedMap, handleCheck, handleCheckAllFiltersInFacet, updateFilteredCells,
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
        checkedMap={checkedMap}
        handleCheckAllFiltersInFacet={handleCheckAllFiltersInFacet}
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
          style={{ 'fontSize': '13px', 'marginLeft': '18px' }}
          onClick={() => {setIsPartlyCollapsed(!isPartlyCollapsed)}}
        >
          {isPartlyCollapsed ? 'More...' : 'Less...'}
        </a>
      }
    </div>
  )
}

/** Get stylized name of facet, optional tooltip, collapse controls */
function FacetHeader({
  facet, checkedMap, handleCheckAllFiltersInFacet, isFullyCollapsed, setIsFullyCollapsed
}) {
  const [facetName, rawFacetName] = parseAnnotationName(facet.annotation)
  const isConventional = getIsConventionalAnnotation(rawFacetName)

  const facetNameStyle = {}
  const tooltipableFacetNameStyle = {
    width: 'content-fit'
  }

  const loadingClass = !facet.isLoaded ? 'loading' : ''
  if (!facet.isLoaded) {
    facetNameStyle.color = '#777'
    facetNameStyle.cursor = 'default'
  }

  let title = 'Author annotation'
  if (isConventional) {
    title = 'Conventional annotation'
    const note = conventionalMetadataGlossary[rawFacetName]
    if (note) {
      title += `.  ${note}`
    }
  }
  title += `.  Name in data: ${rawFacetName}`

  const toggleClass = `cell-filters-${isFullyCollapsed ? 'hidden' : 'shown'}`

  // Assess if facet-level checkbox should be indeterminate, i.e. "-",
  // which is a common state in hierarchical checkboxes to indicate that
  // some lower checkboxes are checked, and some are not.
  const allFiltersInFacet = facet.groups
  const allCheckedFiltersInFacet = checkedMap[facet.annotation]
  const isFacetCheckboxSelected = allFiltersInFacet.length === allCheckedFiltersInFacet.length
  const isIndeterminate = !(
    allCheckedFiltersInFacet.length === 0 ||
    isFacetCheckboxSelected
  )

  return (
    <div>
      <input
        type="checkbox"
        className="cell-facet-header-checkbox"
        data-analytics-name={`facet-${facet.annotation}`}
        name={`facet-${facet.annotation}`}
        onChange={event => {
          handleCheckAllFiltersInFacet(event)
        }}
        checked={isFacetCheckboxSelected}
        ref={input => {
          if (input) {
            input.indeterminate = isIndeterminate
          }
        }}
      />
      <span
        className={`cell-facet-header ${toggleClass}`}
        onClick={() => setIsFullyCollapsed(!isFullyCollapsed)}
      >
        <span className={`cell-facet-name ${loadingClass}`}>
          <span
            style={tooltipableFacetNameStyle}
            data-original-title={title}
            {...tooltipAttrs}
          >
            {facetName}
          </span>
        </span>
        <FacetTools
          isCollapsed={isFullyCollapsed}
          whatToToggle="filter list"
          isLoaded={facet.isLoaded}
        />
      </span>
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


  // TODO: Uncommenting below and replacing `filters` with `sortedFilters` in
  // this function makes the _filter list_ naturally sorted, but subtly
  // (and severely) causes a mismatch between the selected filter label and the
  // group of plotted cells that actually gets hidden in the plot.

  // Naturally sort groups (see https://en.wikipedia.org/wiki/Natural_sort_order)
  // const sortedFilters = facet.groups.sort((a, b) => {
  //   return a[0].localeCompare(b[0], 'en', { numeric: true, ignorePunctuation: true })
  // })

  const facets = cellFaceting.facets.map(facet => {
    // Add counts of matching cells for each filter to its containing facet object
    facet.filterCounts = cellFilterCounts[facet.annotation]

    // Sort categorical filters (i.e., groups)
    const initCounts = cellFaceting.filterCounts[facet.annotation]
    if (initCounts) {
      if (!facet.unsortedGroups) {facet.unsortedGroups = facet.groups}
      const sortedGroups = facet.groups.sort((a, b) => {
        if (initCounts[a] && initCounts[b]) {
          return initCounts[b] - initCounts[a]
        }
      })
      facet.groups = sortedGroups
    }
    return facet
  })

  const [checkedMap, setCheckedMap] = useState(cellFilteringSelection)
  const [colorByFacet, setColorByFacet] = useState(shownAnnotation)
  const shownFacets = facets.filter(facet => facet.groups.length > 1)
  const [isAllListsCollapsed, setIsAllListsCollapsed] = useState(false)

  /** Top header for the "Filter" section, including all-facet controls */
  function FilterSectionHeader({ facets, checkedMap, handleResetFilters, isAllListsCollapsed, setIsAllListsCollapsed }) {
    return (
      <div
        className="filter-section-header"
        onClick={event => {
          if (Array.from(event.target.classList).includes('fa-undo')) {
            // Don't toggle facet collapse on "Reset filters" button click
            return
          }
          setIsAllListsCollapsed(!isAllListsCollapsed)
        }}
      >
        <span
          className="filter-section-name"
          style={{ 'fontWeight': 'bold' }}
          {...tooltipAttrs}
          data-original-title="Use checkboxes to show or hide cells in plots.  Deselected values are
        assigned to the '--Filtered--' group. Hover over this legend entry to highlight."
        >Filter by</span>
        <FacetTools
          isCollapsed={isAllListsCollapsed}
          setIsCollapsed={setIsAllListsCollapsed}
          whatToToggle="all filter lists"
          isLoaded={true}
          isRoot={true}
          facets={facets}
          checkedMap={checkedMap}
          handleResetFilters={handleResetFilters}
        />
      </div>
    )
  }

  /** Add or remove all checked item from list */
  function handleCheckAllFiltersInFacet(event) {
    const facetName = event.target.name.split(':')[0].replace('facet-', '')
    const isCheck = event.target.checked
    const allFiltersInFacet = facets.find(f => f.annotation === facetName).groups
    const updatedList = isCheck ? allFiltersInFacet : []
    checkedMap[facetName] = updatedList
    setCheckedMap(checkedMap)
    updateFilteredCells(checkedMap)
  }

  /** Reset all filters to initial, selected state */
  function handleResetFilters() {
    const initSelection = {}
    facets.forEach(facet => {
      initSelection[facet.annotation] = facet.groups
    })

    setCheckedMap(initSelection)
    updateFilteredCells(initSelection)
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

  const verticalPad = 344 // Accounts for all UI real estate above table header

  const filterSectionHeight = window.innerHeight - verticalPad
  const filterSectionHeightProp = `${filterSectionHeight}px`

  // Apply custom delay to tooltips added after initial pageload
  if (window.$) {window.$('[data-toggle="tooltip"]').tooltip()}

  return (
    <>
      <div>
        <label className="labeled-select">
          <span
            className="cell-filtering-color-by"
            {...tooltipAttrs}
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
          <div className="filter-section" style={{ marginTop: '10px', marginLeft: '-10px' }}>
            <FilterSectionHeader
              facets={facets}
              checkedMap={checkedMap}
              handleResetFilters={handleResetFilters}
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
                    handleCheckAllFiltersInFacet={handleCheckAllFiltersInFacet}
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
