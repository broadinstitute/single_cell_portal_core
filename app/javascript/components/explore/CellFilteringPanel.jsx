
import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faArrowLeft, faChevronDown, faChevronRight, faUndo,
  faSortAlphaDown, faSortAmountDown
} from '@fortawesome/free-solid-svg-icons'

import Select from '~/lib/InstrumentedSelect'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { annotationKeyProperties, clusterSelectStyle } from '~/lib/cluster-utils'
import { log } from '~/lib/metrics-api'


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

/** UI control to update how filters are sorted */
function SortFiltersIcon({ sortKey, setSortKey }) {
  const icon = sortKey === 'count' ? faSortAmountDown : faSortAlphaDown
  const nextSortKey = sortKey === 'count' ? 'label' : 'count'

  return (
    <span
      onClick={() => {
        setSortKey(nextSortKey)
        log('sort-filters', { sortKey })
      }}
      className={`sort-filters sort-filters-${sortKey}`}
      data-analytics-name={`sort-filters sort-filters-${sortKey}`}
      {...tooltipAttrs}
      data-original-title={`Sorted by ${sortKey}; click to sort by ${nextSortKey}`}
    >
      <FontAwesomeIcon icon={icon}/>
    </span>
  )
}

/** Toggle icon for collapsing a list; for each filter list, and all filter lists */
function FacetTools({
  isCollapsed, whatToToggle,
  isLoaded,
  sortKey,
  setSortKey,
  facet=null,
  isRoot=false, hasNondefaultSelection, handleResetFilters
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
      {isLoaded && !isRoot && !isCollapsed &&
      <SortFiltersIcon
        facet={facet}
        sortKey={sortKey}
        setSortKey={setSortKey}
      />
      }
      {isRoot &&
        <ResetFiltersButton
          hasNondefaultSelection={hasNondefaultSelection}
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

/** Determine if user has deselected any filters */
function getHasNondefaultSelection(checkedMap, facets) {
  let numTotalFilters = 0
  facets.forEach(facet => numTotalFilters += facet.groups.length)
  let numCheckedFilters = 0
  Object.entries(checkedMap).forEach(([_, filters]) => {
    numCheckedFilters += filters.length
  })

  const hasNondefaultSelection = numTotalFilters !== numCheckedFilters

  return hasNondefaultSelection
}

/** Button to reset all filters to their default, initial state */
function ResetFiltersButton({ hasNondefaultSelection, handleResetFilters }) {
  const isResetEligible = hasNondefaultSelection
  const resetDisplayClass = isResetEligible ? '' : 'hide-reset'

  return (
    <a
      onClick={() => handleResetFilters()}
      className={`reset-cell-filters ${resetDisplayClass}`}
      data-analytics-name="reset-cell-filters"
      data-toggle="tooltip"
      data-original-title="Reset filter selections"
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
    toggleIcon = <FontAwesomeIcon className="chevron-down" icon={faChevronDown} />
    toggleIconTooltipText = `Hide ${whatToToggle}`
  } else {
    toggleIcon = <FontAwesomeIcon className="chevron-right" icon={faChevronRight} />
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

/** Tiny bar chart showing proportions of passed vs. filtered cells */
function BaselineSparkbar({ baselineCount, passedCount }) {
  const maxWidth = 65

  const selectedWidth = Math.round(maxWidth * (passedCount / baselineCount))

  const maxWidthPx = `${maxWidth}px`
  const passedWidthPx = `${selectedWidth}px`

  const fullClass = baselineCount === passedCount ? ' full' : ''
  const baseTop = passedCount === 0 ? '0' : '2px'

  const passedStyle = { width: passedWidthPx }
  const filteredStyle = { width: maxWidthPx, top: baseTop }

  return (
    <>
      <span className="sparkbar">
        <span className="sparkbar-filtered" style={filteredStyle}></span>
        <span className={`sparkbar-passed ${fullClass}`} style={passedStyle}> </span>
      </span>
    </>
  )
}

/** Get tooltip for quantities shown upon hovering when a filter has been applied */
function getQuantitiesTooltip(baselineCount, passedCount, hasNondefaultSelection) {
  if (!hasNondefaultSelection) {
    return {}
  }

  let tooltipContent
  if (passedCount !== baselineCount) {
    // "Baseline": # cells highlighted _before_ any filtering
    // "Passed": # cells highlighted after filtering
    // "Filtered": # cells _not_ highlighted after filtering
    //
    // These "not highlighted after filtering" cells are the group-specific
    // component of the broader "--Filtered--" group we show in the cluster
    // scatter plot legend, for cells that are plotted in a faint grey.  It's
    // important that this tooltip term for "not highlighted after filtering"
    // matches that other term in the plot legend.

    const percentPassed = Math.round(100 * passedCount / baselineCount)
    const filteredCount = baselineCount - passedCount
    const percentFiltered = Math.round(100 - percentPassed)

    const passedText = `Passed: ${passedCount} (${percentPassed}%)`.replace(/ /g, '&nbsp;')
    const filteredText = `Filtered: ${filteredCount} (${percentFiltered}%)`.replace(/ /g, '&nbsp;')

    tooltipContent =
      `<div>` +
      `Baseline:&nbsp;${baselineCount}<br/>` +
      `<span class="sparkbar-tooltip-passed">${passedText}</span><br/>` +
      `<span class="sparkbar-tooltip-filtered">${filteredText}</span>` +
      `</div>`
  } else {
    tooltipContent = 'All cells passed'.replace(/ /g, '&nbsp;')
  }
  const quantitiesTooltip = {
    'data-original-title': tooltipContent,
    'data-html': true,
    ...tooltipAttrs
  }

  return quantitiesTooltip
}

/** Cell filter component */
function CellFilter({
  facet, filter, isChecked, checkedMap, handleCheck,
  hasNondefaultSelection
}) {
  let facetLabelStyle = {}
  const inputStyle = { 'margin': '1px 5px 0 0', 'verticalAlign': 'top' }
  if (!facet.isLoaded) {
    inputStyle.cursor = 'default'
    facetLabelStyle = { color: '#777', cursor: 'default' }
  }

  const filterDisplayName = filter.replace(/_/g, ' ')

  const baselineCount = facet.originalFilterCounts[filter]
  const passedCount = (facet.filterCounts && facet.filterCounts[filter]) ?? 0
  const quantitiesTooltip = getQuantitiesTooltip(baselineCount, passedCount, hasNondefaultSelection)

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
        <span className="cell-filter-label-text">{filterDisplayName}</span>
        <span
          className="cell-filter-quantities"
          {...quantitiesTooltip}
        >
          <span className="cell-filter-count">
            {facet.filterCounts && facet.filterCounts[filter]}
          </span>
          {hasNondefaultSelection &&
          <BaselineSparkbar
            baselineCount={baselineCount}
            passedCount={passedCount}
          />
          }
        </span>
      </div>
    </label>
  )
}

/** Facet name and collapsible list of filter checkboxes */
function CellFacet({
  facet,
  checkedMap, handleCheck, handleCheckAllFiltersInFacet, updateFilteredCells,
  isAllListsCollapsed, hasNondefaultSelection
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

  const [sortKey, setSortKey] = useState('count')

  const unsortedFilters = facet.unsortedGroups ?? []
  let filters

  //  Naturally sort groups (see https://en.wikipedia.org/wiki/Natural_sort_order)
  if (sortKey === 'label') {
    filters = unsortedFilters.sort((a, b) => {
      return a.localeCompare(b, 'en', { numeric: true, ignorePunctuation: true })
    })
  } else {
    // Sort categorical filters (i.e., groups)
    const filterCounts = facet.originalFilterCounts
    const sortedGroups = unsortedFilters.sort((a, b) => {
      if (filterCounts[a] && filterCounts[b]) {
        return filterCounts[b] - filterCounts[a]
      }
    })
    filters = sortedGroups
  }

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
        sortKey={sortKey}
        setSortKey={setSortKey}
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
            hasNondefaultSelection={hasNondefaultSelection}
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

/** Determine if a list of DOM classes includes one used for the sort-icon */
function includesSortIconClass(domClasses) {
  return (
    domClasses.includes('fa-sort-alpha-down') ||
    domClasses.includes('fa-sort-amount-down') ||
    domClasses.includes('sort-filters')
  )
}

/** Get stylized name of facet, optional tooltip, collapse controls */
function FacetHeader({
  facet, checkedMap, handleCheckAllFiltersInFacet, isFullyCollapsed, setIsFullyCollapsed,
  sortKey, setSortKey
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
  const isFacetCheckboxSelected = allFiltersInFacet?.length === allCheckedFiltersInFacet?.length
  const isIndeterminate = !(
    allCheckedFiltersInFacet?.length === 0 ||
    isFacetCheckboxSelected
  )

  return (
    <>
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
        onClick={event => {
          const domClasses = Array.from(event.target.classList)
          const parentDomClasses = Array.from(event.target.parentNode.classList)
          if (
            includesSortIconClass(domClasses) ||
            domClasses.length === 0 && (
              // Accounts for click on the sort icon SVG `path` element itself
              includesSortIconClass(parentDomClasses)
            )
          ) {
            // Don't toggle facet collapse on sort icon click
            return
          }
          setIsFullyCollapsed(!isFullyCollapsed)
        }}
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
          sortKey={sortKey}
          setSortKey={setSortKey}
          isCollapsed={isFullyCollapsed}
          whatToToggle="filter list"
          facet={facet}
          isLoaded={facet.isLoaded}
        />
      </span>
    </>
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

  const facets = cellFaceting.facets
    .filter(
      facet => facet.isSelectedAnnotation === false && facet.annotation.includes('--group--')
    )
    .map(facet => {
      // Add counts of matching cells for each filter to its containing facet object
      facet.filterCounts = cellFilterCounts[facet.annotation]

      // Sort categorical filters (i.e., groups)
      const initCounts = cellFaceting.filterCounts[facet.annotation]
      if (initCounts) {
        if (!facet.unsortedGroups) {facet.unsortedGroups = facet.groups}
        if (!facet.originalFilterCounts) {facet.originalFilterCounts = initCounts}
        const sortedGroups = facet.groups.sort((a, b) => {
          if (initCounts[a] && initCounts[b]) {
            return initCounts[b] - initCounts[a]
          }
        })
        facet.groups = sortedGroups
      }
      return facet
    })

  const defaultCheckedMap = {}
  Object.entries(cellFilteringSelection).forEach(([key, value]) => {
    if (key.includes('--group--')) {
      defaultCheckedMap[key] = value
    }
  })

  const [checkedMap, setCheckedMap] = useState(defaultCheckedMap)
  const [colorByFacet, setColorByFacet] = useState(shownAnnotation)
  const shownFacets = facets.filter(facet => facet.groups?.length > 1)
  const [isAllListsCollapsed, setIsAllListsCollapsed] = useState(false)

  // Needed to propagate facets from URL to initial checkbox states
  useEffect(() => {
    setCheckedMap(defaultCheckedMap)
  }, Object.values(defaultCheckedMap).join(','))

  /** Top header for the "Filter" section, including all-facet controls */
  function FilterSectionHeader({ hasNondefaultSelection, handleResetFilters, isAllListsCollapsed, setIsAllListsCollapsed }) {
    return (
      <div
        className="filter-section-header"
        onClick={event => {
          const domClasses = Array.from(event.target.classList)
          if (
            domClasses.includes('fa-undo') ||
            domClasses.length === 0
          ) {
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
          facet={null}
          isLoaded={true}
          isRoot={true}
          hasNondefaultSelection={hasNondefaultSelection}
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

  const verticalPad = 295 // Accounts for all UI real estate above table header

  const filterSectionHeight = window.innerHeight - verticalPad
  const filterSectionHeightProp = `${filterSectionHeight}px`

  // Apply custom delay to tooltips added after initial pageload
  if (window.$) {window.$('[data-toggle="tooltip"]').tooltip()}

  const hasNondefaultSelection = getHasNondefaultSelection(checkedMap, facets)

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
              hasNondefaultSelection={hasNondefaultSelection}
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
                    hasNondefaultSelection={hasNondefaultSelection}
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
