import React, { useContext } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faDna, faExclamationCircle, faInfoCircle } from '@fortawesome/free-solid-svg-icons'

import StudyResults from './StudyResults'
import Study from './Study'
import SearchQueryDisplay from './SearchQueryDisplay'
import { UserContext } from 'providers/UserProvider'
import { getNumFacetsAndFilters } from 'providers/StudySearchProvider'


/**
 * handles display of loading, error and results for a list of studies
 * @studySearchState - an object with isLoaded, isLoading, isError, and results properties
 * @studyComponent - the component to use to render individual studies.  If not specified, results/Study.js
 * will be used
 */
const ResultsPanel = ({ studySearchState, studyComponent, noResultsDisplay }) => {
  const featureFlagState = useContext(UserContext).featureFlagsWithDefaults
  const results = studySearchState.results

  let panelContent
  if (studySearchState.isError) {
    panelContent = (
      <div className="error-panel  col-md-6 col-md-offset-3">
        <FontAwesomeIcon
          icon={faExclamationCircle}
          className="left-margin-icon"
        />
        Sorry, an error has occurred. Support has been notified. Please try
        again. If this error persists, or you require assistance, please contact
        support at &nbsp;
        <a href="mailto:scp-support@broadinstitute.zendesk.com">
          scp-support@broadinstitute.zendesk.com
        </a>
      </div>
    )
  } else if (!studySearchState.isLoaded) {
    panelContent = (
      <div className="loading-panel">
        Loading &nbsp;
        <FontAwesomeIcon icon={faDna} className="gene-load-spinner" />
      </div>
    )
  } else if (results.studies && results.studies.length > 0) {
    panelContent = (
      <>
        { featureFlagState && featureFlagState.faceted_search &&
          <SearchQueryDisplay terms={results.termList} facets={results.facets}/> }
        <StudyResults
          results={results}
          StudyComponent={studyComponent ? studyComponent : Study}
          changePage={pageNum => {
            studySearchState.updateSearch({ page: pageNum })
          }}
        />
      </>
    )
  } else {
    noResultsDisplay = noResultsDisplay ? noResultsDisplay : <div> No results found. </div>
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
          <p>By selecting filters, your search targets <b>only studies that use ontology terms</b> in their metadata file.
          <br/>
          Currently, about 30% of public studies supply such metadata.</p>
          Learn more on our <a href="https://github.com/broadinstitute/single_cell_portal/wiki/Search-Studies" target="_blank" rel="noreferrer">wiki</a>, and
          study authors can read our <a href="https://github.com/broadinstitute/single_cell_portal/wiki/Metadata-File#Metadata-powered-Advanced-Search" target="_blank" rel="noreferrer">metadata guide</a>.
        </div>
      </div>
    )
  }
  return resultsFooter
}


export default ResultsPanel
