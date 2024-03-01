
import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faArrowLeft
} from '@fortawesome/free-solid-svg-icons'
import _isEqual from 'lodash/isEqual'

import {
  FacetHeader, FacetTools, tooltipAttrs
} from '~/components/explore/FacetComponents'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { NumericCellFacet } from '~/components/explore/NumericCellFacet'
import Select from '~/lib/InstrumentedSelect'
import { annotationKeyProperties, clusterSelectStyle } from '~/lib/cluster-utils'
import { getFeatureFlagsWithDefaults } from '~/providers/UserProvider'

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

/** Determine if user has deselected any filters */
function getHasNondefaultSelection(selectionMap, facets) {
  const entries = Object.entries(selectionMap)
  for (let i = 0; i < entries.length; i++) {
    const [selectedFacet, selection] = entries[i]

    const facet = facets.find(f => f.annotation === selectedFacet)
    let normDefault = facet.defaultSelection
    let normSelection = selection
    if (facet.type === 'group') {
      // Normalize categorical filters, given order doesn't matter for them
      normDefault = new Set(normDefault)
      normSelection = new Set(normSelection)
    }
    if (!_isEqual(normDefault, normSelection)) {
      return true
    }
  }

  return false
}

/** determine if the filter is checked or not */
function isChecked(annotation, item, selectionMap) {
  return selectionMap[annotation]?.includes(item)
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

/** Cell filter component for categorical group annotation dimension */
function GroupCellFilter({
  facet, filter, isChecked, selectionMap, handleCheck,
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
          checked={isChecked(facet.annotation, filter, selectionMap)}
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

/** Facet header and filters for categorical (i.e., group-based) annotations */
function GroupCellFacet({
  facet,
  selectionMap, handleCheck,
  handleCheckAllFiltersInFacet, updateFilteredCells,
  hasNondefaultSelection, isFullyCollapsed, setIsFullyCollapsed,
  shownFilters, sortKey, setSortKey
}) {
  return (
    <>
      <FacetHeader
        facet={facet}
        selectionMap={selectionMap}
        handleCheckAllFiltersInFacet={handleCheckAllFiltersInFacet}
        isFullyCollapsed={isFullyCollapsed}
        setIsFullyCollapsed={setIsFullyCollapsed}
        sortKey={sortKey}
        setSortKey={setSortKey}
      />
      {facet.type === 'group' && shownFilters.map((filter, i) => {
        return (
          <GroupCellFilter
            facet={facet}
            filter={filter}
            isChecked={isChecked}
            selectionMap={selectionMap}
            handleCheck={handleCheck}
            updateFilteredCells={updateFilteredCells}
            hasNondefaultSelection={hasNondefaultSelection}
            key={i}
          />
        )
      })
      }
    </>
  )
}

/** Facet name and collapsible list of filter checkboxes */
function CellFacet({
  facet,
  selectionMap, handleCheck, handleNumericChange,
  handleCheckAllFiltersInFacet, updateFilteredCells,
  isAllListsCollapsed, hasNondefaultSelection
}) {
  if (
    Object.keys(facet).length === 0 ||
    !('groups' in facet)
  ) {
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
  let filters = facet.groups

  if (facet.type === 'numeric' && filters.length < 2) {
    // If facet is numeric, only show if there are multiple values
    return <></>
  }

  let shownFilters = filters
  let numFiltersPartlyCollapsed = null
  if (facet.type === 'group') {
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
    numFiltersPartlyCollapsed = 5
    if (isPartlyCollapsed) {
      shownFilters = filters.slice(0, numFiltersPartlyCollapsed)
    }
    if (isFullyCollapsed) {
      shownFilters = []
    }
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

  const flags = getFeatureFlagsWithDefaults()
  if (facet.type === 'numeric' && !flags?.show_numeric_cell_filtering) {
    return <></>
  }

  const selection = selectionMap[facet.annotation]

  return (
    <div
      className="cell-facet"
      key={facet.annotation}
      style={facetStyle}
    >
      {facet.type === 'group' &&
          <GroupCellFacet
            facet={facet}
            selectionMap={selectionMap}
            handleCheck={handleCheck}
            handleCheckAllFiltersInFacet={handleCheckAllFiltersInFacet}
            updateFilteredCells={updateFilteredCells}
            isAllListsCollapsed={isAllListsCollapsed}
            hasNondefaultSelection={hasNondefaultSelection}
            isFullyCollapsed={isFullyCollapsed}
            setIsFullyCollapsed={setIsFullyCollapsed}
            shownFilters={shownFilters}
            sortKey={sortKey}
            setSortKey={setSortKey}
          />
      }
      {facet.type === 'numeric' &&
          <NumericCellFacet
            facet={facet}
            filters={shownFilters}
            isChecked={isChecked}
            selection={selection}
            selectionMap={selectionMap}
            handleNumericChange={handleNumericChange}
            updateFilteredCells={updateFilteredCells}
            hasNondefaultSelection={hasNondefaultSelection}
            isFullyCollapsed={isFullyCollapsed}
            setIsFullyCollapsed={setIsFullyCollapsed}
            key={facet.annotation}
          />
      }
      {facet.type === 'group' && !isFullyCollapsed && filters.length > numFiltersPartlyCollapsed &&
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
      facet => facet.isSelectedAnnotation === false
    )
    .map(facet => {
      // Add counts of matching cells for each filter to its containing facet object
      facet.filterCounts = cellFilterCounts[facet.annotation]

      // Sort categorical filters (i.e., groups)
      const initCounts = cellFaceting.filterCounts[facet.annotation]
      if (initCounts) {
        if (!facet.originalFilterCounts) {facet.originalFilterCounts = initCounts}

        if (facet.type === 'group') {
          if (!facet.unsortedGroups) {facet.unsortedGroups = facet.groups}
          const sortedGroups = facet.groups.sort((a, b) => {
            if (initCounts[a] && initCounts[b]) {
              return initCounts[b] - initCounts[a]
            }
          })
          facet.groups = sortedGroups
        }
      }
      return facet
    })

  const defaultSelectionMap = {}
  Object.entries(cellFilteringSelection).forEach(([key, value]) => {
    defaultSelectionMap[key] = value
  })
  // console.log('in CellFilteringPanel, defaultSelectionMap["time_post_partum_days--numeric--study"].toString()', defaultSelectionMap['time_post_partum_days--numeric--study'].toString())

  const [selectionMap, setSelectionMap] = useState(defaultSelectionMap)
  const [colorByFacet, setColorByFacet] = useState(shownAnnotation)
  const shownFacets = facets.filter(facet => facet.type === 'numeric' || facet.groups?.length > 1)

  const [isAllListsCollapsed, setIsAllListsCollapsed] = useState(false)

  // Needed to propagate facets from URL to initial checkbox states
  useEffect(() => {
    setSelectionMap(defaultSelectionMap)
    // console.log('in useEffect1, defaultSelectionMap["time_post_partum_days--numeric--study"].toString()', defaultSelectionMap['time_post_partum_days--numeric--study'].toString())
  }, [Object.values(defaultSelectionMap).join(',')])

  useEffect(() => {
    // setSelectionMap(defaultSelectionMap)
    // console.log('in useEffect2, selectionMap["time_post_partum_days--numeric--study"].toString()', selectionMap['time_post_partum_days--numeric--study'].toString())
  }, [Object.values(selectionMap).join(',')])

  // useEffect(() => {
  //   setSelectionMap(selectionMap)
  // }, [Object.values(selectionMap).join(',')])

  /** Top header for the "Filter" section, including all-facet controls */
  function FilterSectionHeader({
    hasNondefaultSelection, handleResetFilters, isAllListsCollapsed, setIsAllListsCollapsed
  }) {
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
    selectionMap[facetName] = updatedList
    setSelectionMap(selectionMap)
    updateFilteredCells(selectionMap)
  }

  /** Reset all filters to initial, selected state */
  function handleResetFilters() {
    const initSelection = {}
    facets.forEach(facet => {
      initSelection[facet.annotation] = facet.defaultSelection
    })

    setSelectionMap(initSelection)
    updateFilteredCells(initSelection)
  }

  /** Add or remove checked item from list */
  function handleCheck(event) {
    // grab the name of the facet from the check event
    const facetName = event.target.name.split(':')[0]

    let updatedList = selectionMap[facetName] ? [...selectionMap[facetName]] : []

    // if the event was a check then add the checked filter to the list
    if (event.target.checked) {
      updatedList = [...updatedList, event.target.value]
    } else {
      // otherwise the event was an uncheck so remove the filter from the list
      updatedList = updatedList.filter(item => {
        return item !== event.target.value
      })
    }
    // update the selectionMap state with the filter in its updated condition
    selectionMap[facetName] = updatedList
    setSelectionMap(selectionMap)

    // update the filtered cells based on the checked condition of the filters
    updateFilteredCells(selectionMap)
  }

  /** Propagate change in a numeric cell filter */
  function handleNumericChange(facetName, newValues) {
    // console.log('facetName, newValues.toString()', facetName, newValues.toString())
    selectionMap[facetName] = newValues.slice()
    const newSelectionMap = Object.assign({}, selectionMap)
    setSelectionMap(newSelectionMap)

    // update the filtered cells based on the checked condition of the filters
    updateFilteredCells(newSelectionMap)
  }

  // console.log('in CellFilteringPanel, selectionMap["time_post_partum_days--numeric--study"].toString()', selectionMap['time_post_partum_days--numeric--study'].toString())
  const days = selectionMap['time_post_partum_days--numeric--study']
  // console.log('days[0][0][1][0]', days[0][0][1][0])
  if (days[0][0][1][0] === 5) {
    // debugger()
    debugger
  }

  const currentlyInUseAnnotations = { colorBy: '', facets: [] }
  const annotationOptions = getAnnotationOptions(annotationList, cluster)

  const verticalPad = 295 // Accounts for all UI real estate above table header

  const filterSectionHeight = window.innerHeight - verticalPad
  const filterSectionHeightProp = `${filterSectionHeight}px`

  // Apply custom delay to tooltips added after initial pageload
  if (window.$) {window.$('[data-toggle="tooltip"]').tooltip()}

  const hasNondefaultSelection = getHasNondefaultSelection(selectionMap, facets)

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
        { Object.keys(selectionMap).length !== 0 &&
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
                    selectionMap={selectionMap}
                    handleCheck={handleCheck}
                    handleNumericChange={handleNumericChange}
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
