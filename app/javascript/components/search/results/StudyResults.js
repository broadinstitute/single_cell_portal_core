import React from 'react'
import { useTable, usePagination } from 'react-table'

import PagingControl from './PagingControl'

// define these outside the render loop so they don't cause rerender loops
// if they ever need to be dynamic, make sure to use useMemo
const columns = [{ accessor: 'study' }]

/**
 * Component for the content of the 'Studies' tab
 */
export default function StudyResults({ results, changePage, StudyComponent }) {
  // convert to an array of objects with a 'study' property for react-table
  const data = React.useMemo(
    () => results.studies.map(study => {return { study }}),
    [results]
  )

  const {
    getTableProps,
    getTableBodyProps,
    prepareRow,
    rows,
    canPreviousPage,
    canNextPage
  } = useTable({
    columns,
    data,
    // holds pagination states
    initialState: {
      pageIndex: results.currentPage - 1,
      // This will change when there's a way to determine amount of results
      // per page via API endpoint
      pageSize: 5
    },
    pageCount: results.totalPages,
    manualPagination: true
  },
  usePagination)

  let pageControlDisplay = <></>
  if (results.totalPages > 1) {
    pageControlDisplay = <PagingControl currentPage={results.currentPage}
      totalPages={results.totalPages}
      changePage={changePage}
      canPreviousPage={canPreviousPage}
      canNextPage={canNextPage}/>
  }

  function getRowProps(row) {
    const studyClass = row.values.study.inferred_match ? 'inferred-match result-row' : 'result-row'
    return { className: studyClass }
  }
  return (
    <>
      <div className="row results-header">
        <div className="col-md-4 results-totals">
          <strong>{ results.totalStudies }</strong> total studies found
        </div>
        <div className="col-md-4">
          { pageControlDisplay }
        </div>
      </div>
      <table {...getTableProps({ className: 'result-table' })}>
        <tbody {...getTableBodyProps()}>
          {rows.map((row, i) => {
            prepareRow(row)
            return (
              <tr {...row.getRowProps(getRowProps(row))}>
                {row.cells.map(cell => {
                  return (
                    <td key {...cell.getCellProps()}>
                      <StudyComponent study={cell.value}/>
                    </td>
                  )
                })}
              </tr>
            )
          })}
        </tbody>
      </table>
      { pageControlDisplay }
    </>
  )
}
