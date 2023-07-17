import React from 'react'
import { faAngleDoubleLeft, faAngleLeft, faAngleRight, faAngleDoubleRight } from '@fortawesome/free-solid-svg-icons'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'

// Taken from https://codesandbox.io/s/github/tannerlinsley/react-table/tree/master/examples/pagination
const PagingControl = ({ currentPage, totalPages, changePage, canPreviousPage, canNextPage, zeroIndexed=false }) => {
  return (
    <div className="pagination">
      <button
        className="text-button"
        onClick={() => {changePage(zeroIndexed ? 0 : 1)}}
        disabled={!canPreviousPage}
        aria-disabled={!canPreviousPage}
        aria-label='Page to start'>
        <FontAwesomeIcon icon={faAngleDoubleLeft}/>
      </button>
      <button
        className="text-button"
        onClick={() => {changePage(currentPage - 1)}}
        disabled={!canPreviousPage}
        aria-disabled={!canPreviousPage}
        aria-label='Page back'>
        <FontAwesomeIcon icon={faAngleLeft}/>
      </button>
      <span className="currentPage">
          Page {zeroIndexed ? currentPage + 1 : currentPage} of {totalPages}
      </span>
      <button
        className="text-button"
        onClick={() => {changePage(currentPage + 1)}}
        disabled={!canNextPage}
        aria-disabled={!canNextPage}
        aria-label='Page next'>
        <FontAwesomeIcon icon={faAngleRight}/>
      </button>
      <button
        className="text-button"
        onClick={() => {changePage(zeroIndexed ? totalPages - 1 : totalPages)}}
        disabled={!canNextPage}
        aria-disabled={!canNextPage}
        aria-label='Page to end'>
        <FontAwesomeIcon icon={faAngleDoubleRight}/>
      </button>
    </div>
  )
}
export default PagingControl
