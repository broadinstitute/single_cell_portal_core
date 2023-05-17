
import React, { useState, useEffect, useRef } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faArrowLeft, faDownload, faSearch, faTimes, faAngleUp, faAngleDown, faUndo } from '@fortawesome/free-solid-svg-icons'
import Button from 'react-bootstrap/lib/Button'

import PagingControl from '~/components/search/results/PagingControl'
import {
  createColumnHelper,
  flexRender,
  getCoreRowModel,
  getSortedRowModel,
  useReactTable,
  getPaginationRowModel
} from '@tanstack/react-table'

import DifferentialExpressionModal from '~/components/explore/DifferentialExpressionModal'
import DifferentialExpressionGroupPicker from '~/components/visualization/controls/DifferentialExpressionGroupPicker'

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
  const actionColor = '#3D5A87'
  // Whipped up via https://boxy-svg.com/app,
  // based on Alexandria-approved mockup at:
  // https://docs.google.com/presentation/d/1j8zt1Hj4otD593FtkXlBsPw4GsxkU4XOVYXQx3Ec--E/edit#slide=id.g19cbfc5899b_0_9
  return (
    <a
      className="de-dot-plot-button"
      onClick={() => {searchGenes(dotPlotGenes)}}
      data-analytics-name="differential-expression-dot-plot"
      data-toggle="tooltip"
      data-original-title="View dot plot for genes on this differential expression table page"
    >
      <svg viewBox="119.295 104.022 40.338 40.976" width="14" height="14">
        <ellipse style={{ 'fill': actionColor }} cx="130.295" cy="115.041" rx="11" ry="11"></ellipse>
        <ellipse style={{ 'fill': actionColor }} cx="153.18" cy="115.779" rx="2.5" ry="2.5"></ellipse>
        <ellipse style={{ 'fill': actionColor }} cx="128.719" cy="137.129" rx="5" ry="5"></ellipse>
        <ellipse style={{ 'fill': actionColor }} cx="151.633" cy="136.998" rx="8" ry="8"></ellipse>
      </svg>
    </a>
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


const defaultSorting = [
  { id: 'pvalAdj', desc: false },
  { id: 'log2FoldChange', desc: true }
]

/** Table of DE data for genes */
function DifferentialExpressionTable({
  genesToShow, searchGenes, clusterName, annotation, species, numRows,
  bucketId, deFilePath, handleClear
}) {
  const defaultPagination = {
    pageIndex: 0,
    pageSize: numRows
  }

  const [rowSelection, setRowSelection] = useState({})
  const [sorting, setSorting] = React.useState(defaultSorting)
  const [pagination, setPagination] = React.useState(defaultPagination)

  const logProps = {
    species, clusterName, annotation
  }

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
    columnHelper.accessor('log2FoldChange', {
      header: () => (
        <span
          id="log2-fold-change-header"
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
    columnHelper.accessor('pvalAdj', {
      header: () => (
        <span
          id="pval-adj-header"
          className="glossary"
          data-toggle="tooltip"
          data-original-title="p-value adjusted with Benjamini-Hochberg FDR correction">
          Adj. p-value
        </span>
      ),
      cell: deGene => {
        return deGene.getValue()
      }
    })
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

  const verticalPad = 400 // Accounts for all UI real estate above table header
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
        <DotPlotButton dotPlotGenes={dotPlotGenes} searchGenes={searchGenes} />
        <DownloadButton bucketId={bucketId} deFilePath={deFilePath} />
        <DifferentialExpressionResetButton onClick={resetDifferentialExpression} />
        <DifferentialExpressionModal />
      </div>
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
          Help improve this new feature
      </a>
    </>
  )
}

/** Differential expression panel shown at right in Explore tab */
export default function DifferentialExpressionPanel({
  deGroup, deGenes, searchGenes,
  exploreInfo, exploreParamsWithDefaults, setShowDeGroupPicker, setDeGenes, setDeGroup,
  countsByLabel, numRows=50
}) {
  const clusterName = exploreParamsWithDefaults?.cluster
  const bucketId = exploreInfo?.bucketId
  const annotation = getAnnotationObject(exploreParamsWithDefaults, exploreInfo)
  const deObjects = exploreInfo?.differentialExpression

  const delayedDETableLogTimeout = useRef(null)

  // filter text for searching the legend
  const [genesToShow, setGenesToShow] = useState(deGenes)
  const [searchedGene, setSearchedGene] = useState('')

  const [deFilePath, setDeFilePath] = useState(null)

  const species = exploreInfo?.taxonNames

  /** Handle a user pressing the 'x' to clear the field */
  function handleClear() {
    updateSearchedGene('', 'clear')
    setGenesToShow(deGenes)
  }

  /** Only show clear button if text is entered in search box */
  const showClear = searchedGene !== ''

  /** Set searched gene, and log search after 1 second delay */
  function updateSearchedGene(newSearchedGene, trigger) {
    setSearchedGene(newSearchedGene)

    // Log search on DE table after 1 second since last change
    // This prevents logging "searches" on "P", "T", "E", and "N" if
    // the string "PTEN" is typed in a speed plausible for someone who
    // knows they want to search PTEN, without stopping to explore interstitial
    // results in the DE table.
    clearTimeout(delayedDETableLogTimeout.current)
    delayedDETableLogTimeout.current = setTimeout(() => {
      const otherProps = { trigger }
      const genes = [newSearchedGene]
      logDifferentialExpressionTableSearch(genes, species, otherProps)
    }, 1000)
  }

  /** Update genes in table based on what user searches */
  useEffect(() => {
    let filteredGenes
    if (searchedGene === '') {
      filteredGenes = deGenes
    } else {
      const lowerCaseSearchedGene = searchedGene.toLowerCase()
      filteredGenes = deGenes.filter(d => d.name.toLowerCase().includes(lowerCaseSearchedGene))
    }

    setGenesToShow(filteredGenes)
  }, [deGenes, searchedGene])

  return (
    <>
      <DifferentialExpressionGroupPicker
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
      />

      {genesToShow &&
      <>
        <div className="de-search-box">
          <span className="de-search-icon">
            <FontAwesomeIcon icon={faSearch} />
          </span>
          <input
            className="de-search-input no-border"
            name="de-search-input"
            type="text"
            autoComplete="off"
            placeholder="Find a gene" // Consensus per demo, to distinguish from main "Search genes" in same UI
            value={searchedGene}
            onChange={event => updateSearchedGene(event.target.value, 'keydown')}
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
        />
      </>
      }
    </>
  )
}

/** Top matter for differential expression panel shown at right in Explore tab */
export function DifferentialExpressionPanelHeader({
  setDeGenes, setDeGroup, setShowDifferentialExpressionPanel, setShowUpstreamDifferentialExpressionPanel, isUpstream,
  cluster, annotation
}) {
  return (
    <>
      <span>Differential expression</span>
      <button className="action fa-lg"
        onClick={() => {
          setDeGenes(null)
          setDeGroup(null)
          setShowDifferentialExpressionPanel(false)
          setShowUpstreamDifferentialExpressionPanel(false)
        }}
        title="Exit differential expression panel"
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
