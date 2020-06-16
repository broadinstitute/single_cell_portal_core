import React, { useContext } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faDna, faExclamationCircle } from '@fortawesome/free-solid-svg-icons'

import StudyResults from './StudyResults'
import Study from './Study'
import SearchQueryDisplay from './SearchQueryDisplay'
import { FeatureFlagContext } from 'providers/FeatureFlagProvider'

/**
 * handles display of loading, error and results for a list of studies
 * @studySearchState - an object with isLoaded, isLoading, isError, and results properties
 * @studyComponent - the component to use to render individual studies.  If not specified, results/Study.js
 * will be used
 */
const ResultsPanel = ({ studySearchState, studyComponent }) => {
  const featureFlagState = useContext(FeatureFlagContext)
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
        { featureFlagState.faceted_search &&
          <SearchQueryDisplay terms={results.termList} facets={results.facets} /> }
        <StudyResults
          results={results}
          StudyComponent={ studyComponent ? studyComponent : Study }
          changePage={pageNum => {
            studySearchState.updateSearch({ page: pageNum })
          }}
        />
      </>
    )
  } else {
    panelContent = (
      <>
        <SearchQueryDisplay terms={results.termList} facets={results.facets} />
        <p>No results</p>
      </>
    )
  }
  return (
    <div className="results-panel">
      <div className="results-content">{panelContent}</div>
    </div>
  )
}

export default ResultsPanel
