import React, { useState } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faDna } from '@fortawesome/free-solid-svg-icons'

import DotPlot from './DotPlot'
import ClusterControls from './ClusterControls'
import { getAnnotationCellValuesURL, getExpressionHeatmapURL } from 'lib/scp-api'
import { withErrorBoundary } from 'lib/ErrorBoundary'

/** Renders a dotplot and associated cluster/annotation selection controls */
function StudyGeneDotPlot({ study, genes, setCollapseBy, collapseBy }) {
  const [clusterParams, setClusterParams] = useState()

  /** fetch the expression data from the server */
  async function updateAnnotation(params) {
    setClusterParams(params)
  }

  return (
    <div className="row graph-container">
      <div className="col-md-10">
        { clusterParams &&
          <DotPlot expressionValuesURL={getExpressionHeatmapURL(study.accession, genes, clusterParams.cluster)}
           annotationCellValuesURL={
             getAnnotationCellValuesURL(study.accession,
               clusterParams.cluster,
               clusterParams.annotation.name,
               clusterParams.annotation.scope,
               clusterParams.annotation.type)
           }
           annotation={clusterParams.annotation}/>
        }
        { !clusterParams && <FontAwesomeIcon icon={faDna} className="gene-load-spinner"/> }
      </div>
      <div className="col-md-2 graph-controls">
        <ClusterControls studyAccession={study.accession} onChange={updateAnnotation} collapseBy={collapseBy} setCollapseBy={setCollapseBy}/>
      </div>
    </div>
  )
}

// wrap in error boundary so plot/control error doesn't take down the page
export default withErrorBoundary(StudyGeneDotPlot)
