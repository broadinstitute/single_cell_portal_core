
import React, { useEffect, useState } from 'react'
import { useTable, usePagination, useSortBy, useFilters } from 'react-table'
import Modal from 'react-bootstrap/lib/Modal'

import LoadingSpinner from '~/lib/LoadingSpinner'
import { fetchEditableStudies } from '~/lib/scp-api'
import PagingControl from '~/components/search/results/PagingControl'
import ErrorBoundary from '~/lib/ErrorBoundary'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import {
  faSort, faSortDown, faSortUp, faEllipsisV, faTrash, faExclamationTriangle
} from '@fortawesome/free-solid-svg-icons'
import InfoPopup from '~/lib/InfoPopup'


// define these outside the render loop so they don't cause rerender loops
// if they ever need to be dynamic, make sure to use useMemo
const columns = [{
  Header: 'Title ',
  accessor: 'name',
  Cell: ({ value, row: { original: { accession, description } } }) => {
    let shortDesc = description.substring(0, 100)
    if (description.length > 100) {
      shortDesc += '...'
    }
    return <div>
      <a href={`/single_cell/study/${accession}`}>{value}</a><br/>
      <span className="detail">{shortDesc}</span>

    </div>
  },
  sortType: (rowA, rowB) => {
    return rowA.original.name.localeCompare(rowB.original.name, 'en', { numeric: true, ignorePunctuation: true })
  },
  filter: (rows, id, filterValue) => {
    const lowerCaseFilter = filterValue.toLowerCase()
    return rows.filter(row => (
      row.original.name.toLowerCase().includes(lowerCaseFilter) ||
      row.original.description.toLowerCase().includes(lowerCaseFilter) ||
      row.original.ownerEmail.toLowerCase().includes(lowerCaseFilter)
    ))
  },
  Filter: ({ column: { filterValue, setFilter } }) => {
    return <>
      &nbsp; &nbsp;
      <input value={filterValue || ''} style={{ minWidth: '350px', border: 'none', margin: '4px' }}
        onChange={e => setFilter(e.target.value || undefined)}
        placeholder="Filter by name, description, or owner email"
      />
    </>
  }
}, {
  Header: 'Owner ',
  accessor: 'ownerEmail',
  sortType: (rowA, rowB) => {
    return rowA.original.name.localeCompare(rowB.original.name, 'en', { numeric: true, ignorePunctuation: true })
  },
  disableFilters: true
}, {
  Header: 'Created ',
  accessor: 'createdAt',
  Cell: ({ value }) => {
    const date = new Date(value)
    return date.toLocaleDateString('default', { month: 'short', day: 'numeric', year: 'numeric' })
  },
  sortType: (rowA, rowB) => {
    return new Date(rowA.original.createdAt) - new Date(rowB.original.createdAt)
  },
  disableFilters: true
}, {
  Header: 'Visibility ',
  accessor: 'public',
  Cell: ({ value }) => <span className={value ? 'public' : 'detail'}>{value ? 'Public' : 'Private'}</span>,
  sortType: (rowA, rowB) => {
    return rowA.original.public - rowB.original.public
  },
  disableFilters: true
}, {
  Header: 'Visuals ',
  accessor: 'initialized',
  Cell: ({ value }) => <span className={value ? 'initialized' : 'detail'}>{value ? 'Yes' : 'No'}</span>,
  sortType: (rowA, rowB) => {
    return rowA.original.initialized - rowB.original.initialized
  },
  disableFilters: true
}, {
  Header: '',
  accessor: 'accession',
  Cell: ({ row: { original: study } }) => <StudyActionLinks study={study}/>,
  disableSortBy: true,
  disableFilters: true
}]

/** Include Reach router */
export default function MyStudiesPage() {
  const [studyList, setStudyList] = useState([])
  const [isLoading, setIsLoading] = useState(true)

  const data = React.useMemo(
    () => studyList,
    [studyList]
  )

  const {
    getTableProps,
    getTableBodyProps,
    prepareRow,
    headers,
    page,
    gotoPage,
    canPreviousPage,
    canNextPage,
    state: { pageIndex }
  } = useTable({
    columns,
    data,
    // holds pagination states
    initialState: {
      pageIndex: 0,
      pageSize: 10,
      sortBy: [{
        id: 'createdAt',
        desc: true
      }]
    }
  },
  useFilters, useSortBy, usePagination)
  useEffect(() => {
    fetchEditableStudies().then(response => {
      setStudyList(response)
      setIsLoading(false)
    })
    window.document.title = `My studies - Single Cell Portal`
  }, [])

  let pageControlDisplay = <></>
  if (studyList.length > 10) {
    pageControlDisplay = <PagingControl currentPage={pageIndex}
      totalPages={Math.floor(studyList.length / 10) + 1}
      changePage={gotoPage}
      canPreviousPage={canPreviousPage}
      canNextPage={canNextPage}
      zeroIndexed={true}/>
  }

  return (
    <div className="form-terra">
      <br/>
      <LoadingSpinner isLoading={isLoading} testId="my-studies-spinner">
        <table {...getTableProps({ className: 'table-terra min-width-100' })}>
          <thead>
            <tr>
              {headers.map(column => (
                <th {...column.getHeaderProps()}>
                  <span {...column.getSortByToggleProps({ className: 'no-wrap' })}>
                    {column.render('Header')}
                    {!column.disableSortBy && <span>
                      {column.isSorted ? column.isSortedDesc ? <FontAwesomeIcon icon={faSortDown}/> : <FontAwesomeIcon icon={faSortUp}/> : <FontAwesomeIcon icon={faSort}/>}
                    </span> }
                  </span>
                  {column.canFilter && column.render('Filter')}
                </th>
              ))}
            </tr>
          </thead>
          <tbody {...getTableBodyProps()}>
            {page.map((row, i) => {
              prepareRow(row)
              return (
                <tr key={i}>
                  <ErrorBoundary>
                    {row.cells.map((cell, i) => (
                      <td key={i} {...cell.getCellProps()}>
                        {cell.render('Cell')}
                      </td>
                    ))}
                  </ErrorBoundary>
                </tr>
              )
            })}
          </tbody>
        </table>
        { pageControlDisplay }
      </LoadingSpinner>
    </div>
  )
}

/** render the list of action links for a given study */
function StudyActionLinks({ study }) {
  const studyId = study.id.$oid
  const [showDeleteModal, setShowDeleteModal] = useState(false)
  const [isDeleteWorkspace, setIsDeleteWorkspace] = useState(false)
  const [deleteConfirmText, setDeleteConfirmText] = useState('')
  const [isDeleting, setIsDeleting] = useState(false)
  const enableDelete = (!isDeleteWorkspace || deleteConfirmText === 'Delete workspace') && !isDeleting
  const deleteUrl = `/single_cell/studies/${studyId}${isDeleteWorkspace ? '' : '?workspace=persist'}`

  const actionList = <ul className="list-style-none-menu">
    <li><a href={`/single_cell/studies/${studyId}`}>Details</a></li>
    <li><a href={`/single_cell/studies/${studyId}/edit`}>Study settings</a></li>
    <li><a href={`/single_cell/studies/${studyId}/edit`}>Edit name &amp; description</a></li>
    <li><a href={`/single_cell/studies/${studyId}/upload`}>Upload &amp; edit files</a></li>
    <li><a href={`/single_cell/studies/${studyId}/sync`}>Sync workspace files</a></li>
    <li><hr/></li>
    <li><a role="button" className="action" onClick={() => setShowDeleteModal(true)}>
      <FontAwesomeIcon icon={faTrash}/> Delete
    </a></li>
  </ul>

  const target = <span data-analytics-name='study-actions-expand'
    tabIndex="0"
    role="button"
    aria-label={`Menu for study: ${study.name}`}
    aria-haspopup="menu"
    className="btn-icon-circled">
    <FontAwesomeIcon icon={faEllipsisV}/>
  </span>

  const deleteModal = <Modal
    show={showDeleteModal}
    onHide={() => setShowDeleteModal(false)}
    animation={false}>
    <Modal.Body>
      <FontAwesomeIcon icon={faExclamationTriangle} className="alert-warning"/> Delete study:
      "{study.name}"<br/><br/>
      <label><input type="checkbox"
        data-analytics-name="workspace-delete-checkbox"
        onChange={e => setIsDeleteWorkspace(e.target.checked)}
        checked={isDeleteWorkspace}>
      </input> Delete Terra workspace too
      </label>
      <br/><br/>
      { !isDeleteWorkspace &&
        <span className="detail">The Terra workspace and files within it will be preserved</span>
      }
      { isDeleteWorkspace &&
        <div>
          The workspace and all files in the <a href={`study.bucketId`}>workspace bucket</a>
          <span className="strong"> will be destroyed.</span><br/><br/>
          Please type &quot;Delete workspace&quot; to continue:<br/>
          <input type="text" value={deleteConfirmText} onChange={e => setDeleteConfirmText(e.target.value)}/>
        </div>
      }
    </Modal.Body>
    <Modal.Footer>
      <LoadingSpinner isLoading={isDeleting}>
        {(!enableDelete && !isDeleting) &&
          <button
            className="btn terra-secondary-btn"
            disabled={true}>
            <FontAwesomeIcon icon={faTrash} className="alert-danger"/> Delete
          </button>
        }
        {enableDelete && <a data-method="delete"
          role="button"
          className="btn terra-secondary-btn"
          onClick={() => setIsDeleting(true)}
          href={deleteUrl}>
          <FontAwesomeIcon icon={faTrash} className="alert-danger"/> Delete
        </a> }
        { !isDeleting && <a
          role="button"
          className="btn terra-secondary-btn"
          onClick={() => setShowDeleteModal(false)}>
          Cancel
        </a> }
      </LoadingSpinner>
    </Modal.Footer>
  </Modal>

  return <div>
    <InfoPopup
      target={target}
      content={actionList}
      placement="left"
    />
    {deleteModal}
  </div>
}
