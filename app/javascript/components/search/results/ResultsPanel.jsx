import React from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faInfoCircle, faExclamationCircle } from '@fortawesome/free-solid-svg-icons'

import StudyResults from './StudyResults'
import StudySearchResult from './StudySearchResult'
import SearchQueryDisplay from './SearchQueryDisplay'
import { getNumFacetsAndFilters } from '~/providers/StudySearchProvider'
import { serverErrorEnd } from '~/lib/error-utils'
import LoadingSpinner from '~/lib/LoadingSpinner'


/**
 * handles display of loading, error and results for a list of studies
 * @studySearchState - an object with isLoaded, isLoading, isError, and results properties
 * @studyComponent - the component to use to render individual studies.  If not specified, results/StudySearchResult.js
 * will be used
 */
const ResultsPanel = ({ studySearchState, studyComponent, noResultsDisplay, bookmarks }) => {
  const results = studySearchState.results
  const hcaMessage = <div className='flexbox alert alert-warning'>
    <div className="">
      <FontAwesomeIcon icon={faExclamationCircle} className="fa-lg fa-fw icon-left"/>
    </div>
    <p>Broadening your search to include the <a
      className='hca-link'
      onClick={() => studySearchState.updateSearch({ external: 'hca' })}
      data-analytics-event='search-hca-empty-results'>
      Human Cell Atlas Data Portal
    </a> may return more results.</p>
  </div>

  const emptyResultMessage =  <div>
    No results found. { studySearchState?.params?.external === "" ? hcaMessage : null }
  </div>

  let panelContent
  if (studySearchState.isError) {
    panelContent = (
      <div className="error-panel col-md-6 col-md-offset-3">
        { serverErrorEnd }
      </div>
    )
  } else if (!studySearchState.isLoaded) {
    panelContent = (
      <div className="loading-panel">
        Loading &nbsp;
        <LoadingSpinner />
      </div>
    )
  } else if (results.studies && results.studies.length > 0) {
    panelContent = (
      <>
        { <SearchQueryDisplay terms={results.termList}
                              facets={results.facets}
                              bookmarks={bookmarks}
                              studySearchState={studySearchState}/> }
        { }
        <StudyResults
          results={results}
          StudyComponent={studyComponent ? studyComponent : StudySearchResult}
          changePage={pageNum => {
            studySearchState.updateSearch({ page: pageNum })
          }}
        />
      </>
    )
  } else {
    noResultsDisplay = noResultsDisplay ? noResultsDisplay : emptyResultMessage
    panelContent = (
      <>
        <SearchQueryDisplay terms={results.termList} facets={results.facets} />
        {noResultsDisplay}
      </>
    )
  }

  return (
    <div className="results-panel">
      <div className="results-content">
        { panelContent }
        <FacetResultsFooter studySearchState={studySearchState}/>
      </div>
    </div>
  )
}

const FacetResultsFooter = ({ studySearchState }) => {
  let resultsFooter = <div></div>
  if (studySearchState.isLoaded && studySearchState.params &&
      getNumFacetsAndFilters(studySearchState.params.facets)[0] > 0) {
    resultsFooter = (
      <div className="flexbox alert alert-info">
        <div className="">
          <FontAwesomeIcon icon={faInfoCircle} className="fa-lg fa-fw icon-left"/>
        </div>
        <div className="">
          <p>Our advanced search is metadata-powered.
          By selecting filters, your search <b>targets only studies that use ontology terms</b> in their metadata file.
          Many, but not all, public studies supply that metadata.</p>
          Learn more about our search capability on our{' '}
          <a className= "link-darker-blue" href="https://singlecell.zendesk.com/hc/en-us/articles/360061006431-Search-Studies"
            target="_blank" rel="noreferrer">documentation
          </a>.  Study authors looking to make their studies more accessible can read our{' '}
          {/* eslint-disable-next-line max-len */}
          <a className= "link-darker-blue" href="https://singlecell.zendesk.com/hc/en-us/articles/4406379107355-Metadata-powered-Advanced-Search"
            target="_blank" rel="noreferrer"> metadata guide
          </a>.
        </div>
      </div>
    )
  }
  return resultsFooter
}


export default ResultsPanel
