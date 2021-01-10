import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faDna } from '@fortawesome/free-solid-svg-icons'
import _uniqueId from 'lodash/uniqueId'

import { fetchExpressionViolin } from 'lib/scp-api'
import { renderViolinPlot } from 'lib/violin-plot'
import ClusterControls from './ClusterControls'

/** displays a violin plot of expression data for the given gene and study */
export default function StudyViolinPlot({ study, genes, setCollapseBy, collapseBy }) {
  const [isLoaded, setIsLoaded] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [graphElementId] = useState(_uniqueId('study-violin-'))
  const [annotationList, setAnnotationList] = useState(null)

  const showCollapseControl = genes.length > 1
  /** Update controls with cluster parameters */
  function handleControlUpdate(clusterParams) {
    if (clusterParams.userUpdated) {
      loadData(clusterParams)
    }
  }

  /** gets expression data from the server */
  async function loadData(clusterParams) {
    setIsLoading(true)
    let results
    if (!clusterParams) {
      // this is the initial load
      results = await fetchExpressionViolin(study.accession, genes,null,null,null,null,null,collapseBy)
      setAnnotationList(results.annotation_list)
    } else {
      results = await fetchExpressionViolin(study.accession,
        genes,
        clusterParams.cluster,
        clusterParams.annotation.name,
        clusterParams.annotation.type,
        clusterParams.annotation.scope,
        clusterParams.subsample,
        collapseBy)
    }
    setIsLoaded(true)
    setIsLoading(false)
    renderViolinPlot(graphElementId, results)
  }

  useEffect(() => {
    // do a load from the server if this is the initial load
    if (!isLoading && !isLoaded) {
      loadData()
    }
  }, [study.accession, genes[0]])

  return (
    <div className="row graph-container">
      <div className="col-md-10">
        <div
          className="expression-graph"
          id={graphElementId}
          data-testid={graphElementId}
        >
        </div>
        {
          isLoading &&
          <FontAwesomeIcon
            icon={faDna}
            data-testid={`${graphElementId}-loading-icon`}
            className="gene-load-spinner"
          />
        }
      </div>
      <div className="col-md-2 graph-controls">
        <ClusterControls studyAccession={study.accession}
          onChange={handleControlUpdate}
          fetchAnnotationList={false}
          preloadedAnnotationList={annotationList}
          collapseBy={collapseBy}
          setCollapseBy={showCollapseControl ? setCollapseBy : null}/>
      </div>
    </div>
  )
}
