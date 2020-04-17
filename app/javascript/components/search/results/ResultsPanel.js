import React, { useContext } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faDna, faExclamationCircle } from '@fortawesome/free-solid-svg-icons'

import { StudySearchContext } from 'providers/StudySearchProvider'
import StudyResults from './StudyResults'
import Study from './Study'
import SearchQueryDisplay from './SearchQueryDisplay'
import { FeatureFlagContext } from 'providers/FeatureFlagProvider'

/**
 * Component for Results displayed on the homepage
 */
const ResultsPanel = props => {
  const searchContext = useContext(StudySearchContext)
  const featureFlagState = useContext(FeatureFlagContext)
  const results = searchContext.results
  let panelContent
  if (searchContext.isError) {
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
  } else if (!searchContext.isLoaded) {
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
          StudyComponent={ Study }
          changePage={pageNum => {
            searchContext.updateSearch({ page: pageNum })
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
