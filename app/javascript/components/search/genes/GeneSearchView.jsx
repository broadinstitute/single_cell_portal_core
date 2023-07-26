import React, { useContext, useEffect } from 'react'

import { GeneSearchContext } from '~/providers/GeneSearchProvider'
import GeneKeyword from './GeneKeyword'
import ResultsPanel from '~/components/search/results/ResultsPanel'
import StudyGeneExpressions from './StudyGeneExpressions'

/**
  * Renders a gene search control panel and the associated results
  */
export default function GeneSearchView() {
  const geneSearchState = useContext(GeneSearchContext)

  const showStudySearchResults = !geneSearchState.isLoaded &&
                                 !geneSearchState.isLoading &&
                                 !geneSearchState.isError

  const geneSearchPlaceholder = 'Genes (e.g. "PTEN NF2")'

  useEffect(() => {
    // if a search isn't already happening, perform one
    if (showStudySearchResults &&
        !geneSearchState.isLoading &&
        !geneSearchState.isLoaded) {
      geneSearchState.performSearch()
    }
  })

  const helpTextContent = (
    <div>
      Enter a list of one or more genes, separated by spaces.
      <br/>
      Do not include non-genes.
      <br/>
      Search is case-sensitive.
      <br/>
      <br/>
      Examples:
      <ul>
        <li>farsa</li>
        <li>brca1 brca2 pten</li>
      </ul>
    </div>
  )

  const noResultsContent = (
    <div>
      No results found.
      <br/>
      { helpTextContent }
    </div>
  )

  return (
    <div>
      <div className="row">
        <div className="col-md-12 col-sm-12 col-xs-12">
          <span className='text-search search-title'>
          Search by genes
            <GeneKeyword placeholder={geneSearchPlaceholder} helpTextContent={helpTextContent} />
          </span>
        </div>
      </div>
      <div className="row">
        <div className="col-md-12">
          <ResultsPanel
            studySearchState={geneSearchState}
            studyComponent={StudyGeneExpressions}
            noResultsDisplay={noResultsContent} />
        </div>
        <div className="col-md-12">
          <div id="load-more-genes-target"></div>
        </div>
      </div>
    </div>
  )
}
