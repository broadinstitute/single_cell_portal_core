
import React, { useState, useEffect, useRef } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faArrowLeft, faDownload, faSearch, faTimes, faAngleUp, faAngleDown, faUndo, faBullseye
} from '@fortawesome/free-solid-svg-icons'
import Button from 'react-bootstrap/lib/Button'

import PagingControl from '~/components/search/results/PagingControl'
import DifferentialExpressionFilters from './DifferentialExpressionFilters'
import {
  getCanonicalSize, getCanonicalSignificance
} from '~/lib/validation/validate-differential-expression'
import { contactUsLink } from '~/lib/error-utils'


import {
  createColumnHelper,
  flexRender,
  getCoreRowModel,
  getSortedRowModel,
  useReactTable,
  getPaginationRowModel
} from '@tanstack/react-table'

import DifferentialExpressionModal from '~/components/explore/DifferentialExpressionModal'
import {
  OneVsRestDifferentialExpressionGroupPicker, PairwiseDifferentialExpressionGroupPicker
} from '~/components/visualization/controls/DifferentialExpressionGroupPicker'

import {
  logDifferentialExpressionTableSearch,
  logSearchFromDifferentialExpression
} from '~/lib/search-metrics'
import { downloadBucketFile } from '~/lib/scp-api'

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

/** Message shown around DE table for no results, or unfound genes */
function BroadenSearchMessage() {
  return (
    <>
    Try broadening your search, or {contactUsLink} for help.
    </>
  )
}

/** Top matter for differential expression panel shown at right in Explore tab */
export function DifferentialExpressionPanelHeader({
  setDeGenes, setDeGroup, setShowDifferentialExpressionPanel, setShowUpstreamDifferentialExpressionPanel, isUpstream,
  cluster, annotation, setDeGroupB, isAuthorDe, deGenes, togglePanel
}) {
  const deSource = `${isAuthorDe ? 'Author' : 'SCP'}-computed`
  return (
    <>
      <span>Differential expression {deGenes && <span className="margin-left de-source badge badge-inverse">{deSource}</span>}</span>
      <button className="action fa-lg de-exit-panel"
        onClick={() => {
          togglePanel('options')
          setDeGenes(null)
          setDeGroup(null)
          setDeGroupB(null)
          setShowDifferentialExpressionPanel(false)
          setShowUpstreamDifferentialExpressionPanel(false)
        }}
        title="Back to options panel"
        data-analytics-name="differential-expression-panel-exit">
        <FontAwesomeIcon icon={faArrowLeft}/>
      </button>
      {isUpstream &&
        <>
          <div className="de-nondefault-explainer">
          No DE results for:
            <br/><br/>
            <ul className="no-de-summary">
              <li>
                <span className="bold">Clustering</span><br/>
                {cluster}
              </li>
              <br/>
              <li>
                <span className="bold">Annotation</span><br/>
                {annotation.name}
              </li>
            </ul>
            <br/>
          Explore DE results in:
          </div>
        </>
      }
    </>
  )
}

/** A small icon-like button that downloads DE data as a file */
function DownloadButton({ bucketId, deFilePath }) {
  return (
    <a
      className="de-download-button"
      onClick={async () => {await downloadBucketFile(bucketId, deFilePath)}}
      data-analytics-name="differential-expression-download"
      data-toggle="tooltip"
      data-original-title="Download all differential expression data for this group"
    >
      <FontAwesomeIcon icon={faDownload}/>
    </a>
  )
}

/** A small icon-like button that makes a dot plot */
function DotPlotButton({ dotPlotGenes, searchGenes }) {
  // Whipped up via https://boxy-svg.com/app,
  // based on Alexandria-approved mockup at:
  // https://docs.google.com/presentation/d/1j8zt1Hj4otD593FtkXlBsPw4GsxkU4XOVYXQx3Ec--E/edit#slide=id.g19cbfc5899b_0_9
  return (
    <button
      className="de-dot-plot-button btn btn-primary"
      onClick={() => {searchGenes(dotPlotGenes)}}
      data-analytics-name="differential-expression-dot-plot"
      data-toggle="tooltip"
      data-original-title="For genes on this page"
    >
      <svg className="de-dot-plot-icon" viewBox="119.295 104.022 40.338 40.976" width="14" height="14">
        <ellipse style={{ 'fill': '#FFF' }} cx="130.295" cy="115.041" rx="11" ry="11"></ellipse>
        <ellipse style={{ 'fill': '#FFF' }} cx="153.18" cy="115.779" rx="2.5" ry="2.5"></ellipse>
        <ellipse style={{ 'fill': '#FFF' }} cx="128.719" cy="137.129" rx="5" ry="5"></ellipse>
        <ellipse style={{ 'fill': '#FFF' }} cx="151.633" cy="136.998" rx="8" ry="8"></ellipse>
      </svg>
      Dot plot
    </button>
  )
}

/** Button to refresh DE table to original view */
function DifferentialExpressionResetButton({ onClick }) {
  return <a
    onClick={() => onClick()}
    className="de-reset-button"
    data-analytics-name="differential-expression-reset"
    data-toggle="tooltip"
    data-original-title="Reset view in differential expression table"
  >
    <FontAwesomeIcon icon={faUndo}/>
  </a>
}

/**
 * Icon for current sort order direction in table column header
 *
 * @param {String} order Direction of current sort order: 'asc' or 'desc'
 */
function SortIcon({ order }) {
  const isAscending = order === 'asc'
  const dirIcon = isAscending ? faAngleDown : faAngleUp
  return (
    <button className="sort-icon" aria-label="Sort this column">
      <FontAwesomeIcon icon={dirIcon}/>
    </button>
  )
}

const columnHelper = createColumnHelper()

/** Search genes from DE table */
function searchGenesFromTable(selectedGenes, searchGenes, logProps) {
  searchGenes(selectedGenes)

  // Log this search to Mixpanel
  logSearchFromDifferentialExpression(
    logProps.event, selectedGenes, logProps.species, logProps.rank,
    logProps.clusterName, logProps.annotation.name
  )
}

/** Get label and tooltip title for given significance metric */
function getSignificanceAttrs(significanceMetric, isAuthorDe) {
  // Get displayed label for DE table column header and filter slider
  let label
  const labelsBySignificance = {
    'pvalAdj': `Adj. p-value`,
    'qval': 'q-value'
  }
  if (significanceMetric in labelsBySignificance) {
    label = labelsBySignificance[significanceMetric]
  } else {
    label = significanceMetric
  }

  // Get tooltip title shown upon hovering over significance DE column header
  let tooltipTitle
  const fdrCorrectionMethod = isAuthorDe ? '' : 'Benjamini-Hochberg '
  const titlesBySignificance = {
    'pvalAdj': `p-value adjusted with ${fdrCorrectionMethod}FDR correction`,
    'qval': 'Expected positive false discovery rate'
  }
  if (significanceMetric in titlesBySignificance) {
    tooltipTitle = titlesBySignificance[significanceMetric]
  } else {
    tooltipTitle = 'Significance metric provided by author'
  }

  return [label, tooltipTitle]
}

/** Table of DE data for genes */
function DifferentialExpressionTable({
  genesToShow, searchGenes, clusterName, annotation, species, numRows,
  bucketId, deFilePath, handleClear,
  isAuthorDe, sizeMetric, significanceMetric,
  unfoundGenes, searchedGenes, setSearchedGenes
}) {
  const defaultPagination = {
    pageIndex: 0,
    pageSize: numRows
  }

  const defaultSorting = [
    { id: 'significance', desc: false },
    { id: 'size', desc: true }
  ]

  const [rowSelection, setRowSelection] = useState({})
  const [sorting, setSorting] = React.useState(defaultSorting)
  const [pagination, setPagination] = React.useState(defaultPagination)

  const logProps = {
    species, clusterName, annotation
  }

  const [
    significanceLabel,
    significanceTooltip
  ] = getSignificanceAttrs(significanceMetric, isAuthorDe)

  const significanceColumnHelper = columnHelper.accessor('significance', {
    header: () => (
      <span
        id="significance-header"
        className="glossary"
        data-toggle="tooltip"
        data-original-title={significanceTooltip}>
        {significanceLabel}
      </span>
    ),
    cell: deGene => {
      return deGene.getValue()
    }
  })

  const columns = React.useMemo(() => [
    columnHelper.accessor('name', {
      header: 'Name',
      cell: deGene => {
        return (
          <label
            title="Click to view gene expression.  Arrow down (↓) and up (↑) to quickly scan."
          >
            <input
              type="radio"
              name="selected-gene-de-table"
              data-analytics-name="selected-gene-differential-expression"
              value={deGene.getValue()}
              onChange={event => {
                deGene.table.resetRowSelection(deGene.row)
                deGene.table.setRowSelection(deGene.row)

                logProps.event = event
                logProps.rank = deGene.i

                searchGenesFromTable([deGene.getValue()], searchGenes, logProps)

                deGene.row.getToggleSelectedHandler()
              }}/>
            {deGene.getValue()}
          </label>
        )
      }
    }),

    // TODO (SCP-5352): Enable deeper customization for DE metric label, e.g. size
    columnHelper.accessor('size', {
      header: () => (
        <span
          id="size-header"
          className="glossary"
          data-toggle="tooltip"
          data-original-title="Log (base 2) of fold change">
          log<sub>2</sub>(FC)
        </span>
      ),
      cell: deGene => {
        return deGene.getValue()
      }
    }),
    significanceColumnHelper
  ]
  , [genesToShow]
  )

  const data = React.useMemo(
    () => genesToShow,
    [genesToShow]
  )

  const table = useReactTable({
    columns,
    data,
    getCoreRowModel: getCoreRowModel(),
    state: {
      rowSelection,
      sorting,
      pagination
    },
    onRowSelectionChange: setRowSelection,
    getSortedRowModel: getSortedRowModel(),
    enableMultisort: true,
    onPaginationChange: setPagination,
    onSortingChange: setSorting,
    getPaginationRowModel: getPaginationRowModel()
  })

  const dotPlotGenes = table.getPaginationRowModel().rows.slice(0, numRows).map(row => (
    row.getAllCells().map(cell => {
      return cell.getValue()
    })[0]
  ))

  const numGenesToShow = genesToShow.length

  const isShowingUnfoundGenes = unfoundGenes.length > 0 && numGenesToShow > 0

  let verticalPad = 540 // Accounts for all UI real estate above table header

  // Retain layout to paginate w/o scrolling
  if (isShowingUnfoundGenes) {verticalPad += 38}
  if (window.innerWidth < 1415) {verticalPad += 24}

  const tableHeight = window.innerHeight - verticalPad

  /** Put DE table back to its original state */
  function resetDifferentialExpression() {
    setRowSelection({})
    setSorting(defaultSorting)
    setPagination(defaultPagination)
    handleClear()
  }


  return (
    <>
      <div className="de-table-buttons">
        {numGenesToShow > 0 &&
        <>
          <DotPlotButton dotPlotGenes={dotPlotGenes} searchGenes={searchGenes} />
          <DownloadButton bucketId={bucketId} deFilePath={deFilePath} />
        </>
        }
        <DifferentialExpressionResetButton onClick={resetDifferentialExpression} />
        <DifferentialExpressionModal />
      </div>
      {isShowingUnfoundGenes > 0 &&
          <UnfoundGenesContainer
            unfoundGenes={unfoundGenes}
            searchedGenes={searchedGenes}
            setSearchedGenes={setSearchedGenes}
          />
      }
      {numGenesToShow === 0 &&
      <div className="de-no-genes-found">
        <span className="bold">No genes found</span>.<br/><br/>

        <BroadenSearchMessage />
      </div>
      }
      {numGenesToShow > 0 &&
      <>
        <table
          className="de-table table table-terra table-scp-compact"
          style={{ height: `${tableHeight}px` }}
        >
          <thead>
            {table.getHeaderGroups().map(headerGroup => (
              <tr key={headerGroup.id}>
                {headerGroup.headers.map(header => (
                  <th key={header.id}>
                    {header.isPlaceholder ? null : (
                      <div
                        {...{
                          style: header.column.getCanSort() ?
                            { cursor: 'pointer', userSelect: 'none' } :
                            '',
                          onClick: header.column.getToggleSortingHandler()
                        }}
                      >
                        {flexRender(
                          header.column.columnDef.header,
                          header.getContext()
                        )}
                        {{
                          asc: <SortIcon order='asc' />,
                          desc: <SortIcon order='desc' />
                        }[header.column.getIsSorted()] ?? null}
                      </div>
                    )}
                  </th>
                ))}
              </tr>
            ))}
          </thead>
          <tbody>
            {table.getRowModel().rows.slice(0, numRows).map(row => (
              <tr className="de-gene-row" key={row.id}>
                {row.getVisibleCells().map(cell => (
                  <td key={cell.id}>
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </td>
                ))}
              </tr>
            )
            )}
          </tbody>
        </table>
        <PagingControl
          currentPage={table.getState().pagination.pageIndex}
          totalPages={table.getPageCount()}
          changePage={table.setPageIndex}
          canPreviousPage={table.getCanPreviousPage()}
          canNextPage={table.getCanNextPage()}
          zeroIndexed={true}
        />
        <a href="https://forms.gle/qPGH5J9oFkurpbD76" target="_blank" title="Take a 1 minute survey">
          Help improve this feature
        </a>
      </>
      }

    </>
  )
}

/** Apply range filters to DE genes */
function rangeFilterGenes(deFacets, deGenes, activeFacets) {
  if (!deGenes || !Object.values(deFacets).some(filters => filters.length > 0)) {
    return deGenes
  }

  const facetEntries = Object.entries(deFacets)
  const filteredGenes = deGenes.filter(deGene => {
    let isMatch = true
    facetEntries.forEach(([facetName, filters]) => {
      if (
        filters.length === 0 ||
        activeFacets[facetName] === false
      ) {
        return
      }
      let satisfiesFilters = false
      const metricValue = deGene[facetName]
      filters.forEach(range => {
        if (metricValue >= range.min && metricValue <= range.max) {
          satisfiesFilters = true
        }
      })
      if (!satisfiesFilters) {isMatch = false}
    })
    return isMatch
  })

  return filteredGenes
}

/** Splits "FOO,BAR", "FOO BAR", or "FOO, BAR" into array */
function splitSearchedGenesString(searchedGenes) {
  if (Array.isArray(searchedGenes)) {return searchedGenes}
  if (searchedGenes === '') {return []}
  return searchedGenes.split(/[ ,]+/)
    .filter(text => text !== '')
}

/** Return hits for substring text search on DE gene names */
function searchGeneNames(searchedGenes, deGenes, findMode) {
  let texts = [searchedGenes]

  if (searchedGenes === '') {
    return [deGenes, texts]
  }

  texts = splitSearchedGenesString(searchedGenes)

  const lowerCaseTexts = texts.map(text => text.toLowerCase())

  const filteredGenes = deGenes.filter(deGene => {
    const lcGeneName = deGene.name.toLowerCase()
    return lowerCaseTexts.some(lcText => {
      if (findMode === 'full') {
        return lcGeneName === lcText
      } else {
        return lcGeneName.includes(lcText)
      }
    })
  })

  return [filteredGenes, texts]
}

/** Apply "Find a gene" and range slider facets to DE genes, return matches */
function filterGenes(searchedGenes, deGenes, deFacets, activeFacets, findMode) {
  let unfoundNames = []
  if (!deGenes) {return [deGenes, unfoundNames]}

  let [filteredGenes, texts] =
    searchGeneNames(searchedGenes, deGenes, findMode)
  filteredGenes = rangeFilterGenes(deFacets, filteredGenes, activeFacets)

  unfoundNames = texts.filter(
    text => !filteredGenes.some(gene => {
      const lcGeneName = gene.name.toLowerCase()
      const lcText = text.toLowerCase()
      if (findMode === 'full') {
        return lcGeneName === lcText
      } else {
        return lcGeneName.includes(lcText)
      }
    })
  ).filter(name => name !== '')
  return [filteredGenes, unfoundNames]
}

/** Copy text user's system clipboard */
function copyToClipboard(text) {
  navigator.clipboard.writeText(text)
}

/** Clear tooltips, i.e. close / remove any open small black tooltips */
function clearTooltips() {
  document.querySelectorAll('.tooltip.fade.top.in').forEach(e => e.remove())
}

/** Copy unfound genes to user's system clipboard */
function copyUnfoundGenes(unfoundGenes) {
  const numUnfound = unfoundGenes.length
  const unfound = unfoundGenes.join(', ')
  copyToClipboard(`Genes not found (${numUnfound}): ${unfound}`)
}

/** Clear gene names that haven't been found in multi-gene DE search */
function clearUnfoundGeneNames(unfoundGenes, searchedGenes, setSearchedGenes) {
  const searchedGenesArray = splitSearchedGenesString(searchedGenes)
  const newSearchedGenes = searchedGenesArray.filter(g => !unfoundGenes.includes(g))
  setSearchedGenes(newSearchedGenes.join(' '))

  clearTooltips()
}

/** Summarize genes not found among DE query results */
function UnfoundGenesContainer({ unfoundGenes, searchedGenes, setSearchedGenes }) {
  const numShownUnfound = window.innerWidth >= 1370 ? 2 : 1 // For responsive layout

  return (
    <div className="unfound-genes-container">
          Genes not found:&nbsp;
      {unfoundGenes.slice(0, numShownUnfound).map(unfoundGene => {
        const id = `unfound-gene-${unfoundGene}`
        return (<span
          className="unfound-gene"
          key={id}
          id={id}>
          {unfoundGene}
        </span>)
      })}
      {unfoundGenes.length > numShownUnfound &&
        <>
          <span>and&nbsp;
            <span
              className="unfound-genes-list glossary"
              data-toggle="tooltip"
              data-original-title={`Unfound gene names: ${unfoundGenes.join(', ')}`}
            >{unfoundGenes.length - numShownUnfound} more</span>
          </span>
          <button
            className='btn-copy-unfound'
            onClick={() => {copyUnfoundGenes(unfoundGenes)}}
            data-analytics-name='unfound-genes-copy'
            data-toggle="tooltip"
            data-original-title="Copy unfound gene names"
          >
            <i className="far fa-copy"></i>
          </button>
        </>
      }
      <Button
        type="button"
        data-analytics-name="clear-de-unfound-genes"
        className="clear-de-search-icon clear-de-unfound-genes-icon"
        data-toggle="tooltip"
        data-original-title="Clear unfound gene names"
        onClick={() => {clearUnfoundGeneNames(unfoundGenes, searchedGenes, setSearchedGenes)}} >
        <FontAwesomeIcon icon={faTimes} />
      </Button>

    </div>
  )
}

/** Differential expression panel shown at right in Explore tab */
export default function DifferentialExpressionPanel({
  deGroup, deGenes, searchGenes,
  exploreInfo, exploreParamsWithDefaults, setShowDeGroupPicker, setDeGenes, setDeGroup,
  countsByLabel, hasOneVsRestDe, hasPairwiseDe, isAuthorDe, deHeaders, deGroupB, setDeGroupB, numRows=50
}) {
  const clusterName = exploreParamsWithDefaults?.cluster
  const bucketId = exploreInfo?.bucketId
  const annotation = getAnnotationObject(exploreParamsWithDefaults, exploreInfo)
  const deObjects = exploreInfo?.differentialExpression

  const delayedDETableLogTimeout = useRef(null)

  const defaultDeFacets = {
    'size': [{ min: -Infinity, max: 0.26 }, { min: 0.26, max: Infinity }]
  }

  const sizeMetric = getCanonicalSize(deHeaders.size)
  let significanceMetric = 'pvalAdj'
  if (isAuthorDe) {
    significanceMetric = getCanonicalSignificance(deHeaders.significance)
  }
  defaultDeFacets['significance'] = [{ min: 0, max: 0.05 }]
  const defaultActiveFacets = { 'size': true, 'significance': true }
  const [deFacets, setDeFacets] = useState(defaultDeFacets)
  const [activeFacets, setActiveFacets] = useState(defaultActiveFacets)

  // Whether to match on full string or partial string for each token in "Find genes"
  const [findMode, setFindMode] = useState('partial')

  const filteredDeGenes = rangeFilterGenes(deFacets, deGenes, activeFacets)

  // filter text for searching the legend
  const [genesToShow, setGenesToShow] = useState(filteredDeGenes)
  const [searchedGenes, setSearchedGenes] = useState('')
  const [unfoundGenes, setUnfoundGenes] = useState([])

  const [deFilePath, setDeFilePath] = useState(null)

  const species = exploreInfo?.taxonNames

  /** Change filter values for range slider facets */
  function updateDeFacets(newFacets, metric) {
    setDeFacets(newFacets)
    const [filteredGenes, unfoundNames] = filterGenes(searchedGenes, deGenes, newFacets, activeFacets, findMode)
    setGenesToShow(filteredGenes)
    setUnfoundGenes(unfoundNames)

    const otherProps = { trigger: 'update-facet', facet: metric }

    const searchedGenesArray = splitSearchedGenesString(searchedGenes)
    logDifferentialExpressionTableSearch(searchedGenesArray, species, otherProps)
  }

  /** Enable or disable slider range facet; preserve filter in background */
  function toggleDeFacet(metric) {
    const newActiveFacets = Object.assign(activeFacets, {})
    newActiveFacets[metric] = !newActiveFacets[metric]

    const [filteredGenes, unfoundNames] = filterGenes(searchedGenes, deGenes, deFacets, newActiveFacets, findMode)

    setActiveFacets(newActiveFacets)
    setGenesToShow(filteredGenes)
    setUnfoundGenes(unfoundNames)

    const otherProps = { trigger: 'toggle-facet', facet: metric }
    const searchedGenesArray = splitSearchedGenesString(searchedGenes)
    logDifferentialExpressionTableSearch(searchedGenesArray, species, otherProps)
  }

  /** Handle a user pressing the 'x' to clear the 'Find a gene' field */
  function handleClear() {
    updateSearchedGenes('', 'clear')

    // Clicking 'x' doesn't clear facets, so apply any active facets
    const [filteredGenes, unfoundNames] = filterGenes('', deGenes, deFacets, activeFacets, findMode)

    setGenesToShow(filteredGenes)
    setUnfoundGenes(unfoundNames)
  }

  /** Switch match mode for "Find genes" */
  function handleFindModeToggle() {
    const newFindMode = findMode === 'partial' ? 'full' : 'partial'
    setFindMode(newFindMode)
    clearTooltips()
  }

  /** Only show clear button if text is entered in search box */
  const showClear = searchedGenes !== ''

  /** Set searched gene, and log search after 1 second delay */
  function updateSearchedGenes(newSearchedGenes, trigger) {
    newSearchedGenes =
      newSearchedGenes
        .replace(/\r?\n/g, ' ') // Replace newlines (Unix- or Windows-style) with spaces
        .replace(/\t/g, ' ')

    setSearchedGenes(newSearchedGenes)

    // Log search on DE table after 1 second since last change
    // This prevents logging "searches" on "P", "T", "E", and "N" if
    // the string "PTEN" is typed in a speed plausible for someone who
    // knows they want to search PTEN, without stopping to explore interstitial
    // results in the DE table.
    clearTimeout(delayedDETableLogTimeout.current)
    delayedDETableLogTimeout.current = setTimeout(() => {
      const otherProps = { trigger }
      const genes = [newSearchedGenes]
      const searchedGenesArray = splitSearchedGenesString(newSearchedGenes)
      logDifferentialExpressionTableSearch(searchedGenesArray, species, otherProps)
    }, 1000)
  }

  /** Update genes in table based on what user searches, filters */
  useEffect(() => {
    const [filteredGenes, unfoundNames] = filterGenes(searchedGenes, deGenes, deFacets, activeFacets, findMode)
    setGenesToShow(filteredGenes)
    setUnfoundGenes(unfoundNames)
  }, [deGenes, searchedGenes, findMode])

  return (
    <>
      {!hasPairwiseDe &&
        <OneVsRestDifferentialExpressionGroupPicker
          bucketId={bucketId}
          clusterName={clusterName}
          annotation={annotation}
          setShowDeGroupPicker={setShowDeGroupPicker}
          deGenes={deGenes}
          setDeGenes={setDeGenes}
          deGroup={deGroup}
          setDeGroup={setDeGroup}
          countsByLabel={countsByLabel}
          deObjects={deObjects}
          setDeFilePath={setDeFilePath}
          isAuthorDe={isAuthorDe}
          sizeMetric={sizeMetric}
          significanceMetric={significanceMetric}
        />
      }
      {hasPairwiseDe &&
        <PairwiseDifferentialExpressionGroupPicker
          bucketId={bucketId}
          clusterName={clusterName}
          annotation={annotation}
          setShowDeGroupPicker={setShowDeGroupPicker}
          deGenes={deGenes}
          setDeGenes={setDeGenes}
          deGroup={deGroup}
          setDeGroup={setDeGroup}
          countsByLabel={countsByLabel}
          deObjects={deObjects}
          setDeFilePath={setDeFilePath}
          deGroupB={deGroupB}
          setDeGroupB={setDeGroupB}
          hasOneVsRestDe={hasOneVsRestDe}
          sizeMetric={sizeMetric}
          significanceMetric={significanceMetric}
        />
      }

      {
        (
          (!hasPairwiseDe && genesToShow) ||
          (hasPairwiseDe && deGroupB && genesToShow)
        ) &&
      <>
        <DifferentialExpressionFilters
          deFacets={deFacets}
          activeFacets={activeFacets}
          updateDeFacets={updateDeFacets}
          toggleDeFacet={toggleDeFacet}
          hasPairwiseDe={hasPairwiseDe}
          sizeMetric={sizeMetric}
          significanceMetric={significanceMetric}
        />
        <div className="de-search-box">
          <span className="de-search-icon">
            <FontAwesomeIcon icon={faSearch} />
          </span>
          <input
            className="de-search-input no-border"
            name="de-search-input"
            type="text"
            autoComplete="off"
            placeholder="Find genes" // Distinguishing from main "Search genes" in same UI
            value={searchedGenes}
            onChange={event => updateSearchedGenes(event.target.value, 'keydown')}
            data-analytics-name="differential-expression-search"
          />
          { showClear && <Button
            type="button"
            data-analytics-name="clear-de-search"
            className="clear-de-search-icon"
            aria-label="Clear"
            onClick={handleClear} >
            <FontAwesomeIcon icon={faTimes} />
          </Button> }
        </div>
        {searchedGenes.length > 0 &&
          <a
            data-analytics-name="de-find-mode"
            className={`de-find-mode-icon ${findMode}`}
            data-toggle="tooltip"
            data-original-title={
              `Matching ${findMode} names.  Click for ${findMode === 'partial' ? 'only full' : 'partial'} matches.`
            }
            onClick={handleFindModeToggle} >
            <FontAwesomeIcon icon={faBullseye} />
          </a>
        }
        <DifferentialExpressionTable
          genesToShow={genesToShow}
          searchGenes={searchGenes}
          clusterName={clusterName}
          annotation={annotation}
          species={species}
          numRows={numRows}
          bucketId={bucketId}
          deFilePath={deFilePath}
          handleClear={handleClear}
          isAuthorDe={hasPairwiseDe}
          sizeMetric={sizeMetric}
          significanceMetric={significanceMetric}
          deFacets={deFacets}
          unfoundGenes={unfoundGenes}
          searchedGenes={searchedGenes}
          setSearchedGenes={setSearchedGenes}
        />
      </>
      }
    </>
  )
}
