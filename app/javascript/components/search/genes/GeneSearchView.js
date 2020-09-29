import React, { useContext, useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faPlusSquare, faMinusSquare } from '@fortawesome/free-solid-svg-icons'

import { GeneSearchContext } from 'providers/GeneSearchProvider'
import GeneKeyword from './GeneKeyword'
import { hasSearchParams, StudySearchContext } from 'providers/StudySearchProvider'
import SearchPanel from 'components/search/controls/SearchPanel'
import ResultsPanel from 'components/search/results/ResultsPanel'
import StudyGeneExpressions from './StudyGeneExpressions'
import { FeatureFlagContext } from 'providers/FeatureFlagProvider'


/**
  * Renders a gene search control panel and the associated results
  * can also show study filter controls if the feature flag gene_study_filter is true
  */
export default function GeneSearchView() {
  const featureFlagState = useContext(FeatureFlagContext)
  const geneSearchState = useContext(GeneSearchContext)
  const studySearchState = useContext(StudySearchContext)

  const [showStudyControls, setShowStudyControls] = useState(hasSearchParams(studySearchState.params))


  const showStudySearchResults = !geneSearchState.isLoaded &&
                                 !geneSearchState.isLoading &&
                                 !geneSearchState.isError

  let geneSearchPlaceholder = 'Search for genes across all studies'
  if (hasSearchParams(studySearchState.params) && featureFlagState.gene_study_filter) {
    geneSearchPlaceholder = 'Search for genes in the filtered studies'
  }

  useEffect(() => {
    // if a search isn't already happening, perform one
    if (showStudySearchResults &&
        !geneSearchState.isLoading &&
        !geneSearchState.isLoaded) {
      geneSearchState.performSearch()
    }
  })

  return (
    <div>
      <div className="row">
        <div className="col-md-12 col-sm-12 col-xs-12">
          <GeneKeyword placeholder={geneSearchPlaceholder}/>
        </div>
      </div>
      { featureFlagState.gene_study_filter &&
        <div className="row gene-study-filter">
          <div className="col-md-2 text-right">
            Study Filter &nbsp;
            <FontAwesomeIcon icon={showStudyControls ? faMinusSquare : faPlusSquare}
              className="action"
              onClick={() => {setShowStudyControls(!showStudyControls)}}/>

          </div>
          <div className="col-md-10">
            { showStudyControls &&
              <SearchPanel
                keywordPrompt="Filter studies by keyword"
                showCommonButtons={false}
                showDownloadButton={false}/> }
          </div>
        </div> }
      <div className="row">
        <div className="col-md-12">
          <ResultsPanel
            studySearchState={geneSearchState}
            studyComponent={StudyGeneExpressions}/>
        </div>
        <div className="col-md-12">
          <div id="load-more-genes-target"></div>
        </div>
      </div>
    </div>
  )
}
