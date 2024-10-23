/**
 * Code shared by group cell facets, numeric cell facets, and/or cell filtering panel
 */

import React from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faChevronDown, faChevronRight, faUndo,
  faSortAlphaDown, faSortAmountDown
} from '@fortawesome/free-solid-svg-icons'

import LoadingSpinner from '~/lib/LoadingSpinner'
import { log } from '~/lib/metrics-api'

export const tooltipAttrs = {
  'data-toggle': 'tooltip',
  'data-delay': '{"show": 150}' // Avoid flurry of tooltips on passing hover
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

/** Determine if a list of DOM classes includes one used for the sort-icon */
function includesSortIconClass(domClasses) {
  return (
    domClasses.includes('fa-sort-alpha-down') ||
    domClasses.includes('fa-sort-amount-down') ||
    domClasses.includes('sort-filters')
  )
}

/** Convert e.g. "cell_type__ontology_label" to "Cell type" */
export function parseAnnotationName(annotationIdentifier) {
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
export function FacetTools({
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
      {isLoaded && !isRoot && !isCollapsed && facet.type === 'group' &&
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

/** Get stylized name of facet, optional tooltip, collapse controls */
export function FacetHeader({
  facet, selectionMap, handleCheckAllFiltersInFacet, handleResetFacet,
  isFullyCollapsed, setIsFullyCollapsed,
  sortKey, setSortKey,
  numericHasNondefaultSelection
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
  const allCheckedFiltersInFacet = selectionMap[facet.annotation]
  const isFacetCheckboxSelected = allFiltersInFacet?.length === allCheckedFiltersInFacet?.length
  const isIndeterminate = !(
    allCheckedFiltersInFacet?.length === 0 ||
    isFacetCheckboxSelected
  )

  return (
    <>
      {facet.type === 'group' &&
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
      }
      {facet.type === 'numeric' &&
        <a
          onClick={() => {
            handleResetFacet(facet)
          }}
          className="reset-facet"
          data-toggle="tooltip"
          data-original-title="Reset selection"
          style={{ 'visibility': numericHasNondefaultSelection ? 'visible' : 'hidden' }}
        >
          <FontAwesomeIcon icon={faUndo}/>
        </a>
      }
      <span
        className={`cell-facet-header cell-facet-header-${facet.type} ${toggleClass}`}
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
