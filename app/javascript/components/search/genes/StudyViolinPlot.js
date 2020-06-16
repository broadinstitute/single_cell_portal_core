import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faDna } from '@fortawesome/free-solid-svg-icons'

import { fetchExpressionViolin } from 'lib/scp-api'
import createTracesAndLayout from 'lib/kernel-functions'
import { plot } from 'lib/plot'

/** gets a unique id for a study gene graph to be rendered at */
function getGraphElementId(study, gene) {
  return `expGraph-${study.accession}-${gene}`
}

/** displays a violin plot of expression data for the given gene and study */
export default function StudyViolinPlot({ study, gene }) {
  const [isLoaded, setIsLoaded] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [clusterOptions, setClusterOptions] = useState([])
  const [annotationOptions, setAnnotationOptions] =
    useState({ 'Study Wide': [], 'Cluster-Based': [] })
  const [subsamplingOptions, setSubsamplingOptions] = useState([])
  const [renderParams, setRenderParams] = useState({
    userUpdated: false,
    cluster: '',
    annotation: '',
    subsample: ''
  })

  /** copied from legacy application.js */
  function parseResultsToArray(results) {
    const keys = Object.keys(results.values)
    return keys.sort().map(key => {
      return [key, results.values[key].y]
    })
  }

  /** handles changes in select controls.  merges newParams into old params */
  function updateRenderParams(newParams) {
    const mergedParams = Object.assign({}, renderParams, newParams)
    mergedParams.userUpdated = true
    setRenderParams(mergedParams)
  }

  /** Formats expression data for Plotly, renders chart */
  function parseAndPlot(results) {
    // The code below is heavily borrowed from legacy application.js
    const dataArray = parseResultsToArray(results)
    const jitter = results.values_jitter ? results.values_jitter : ''
    const traceData = createTracesAndLayout(
      dataArray, results.rendered_cluster, jitter, results.y_axis_title
    )
    const expressionData = [].concat.apply([], traceData[0])
    const expressionLayout = traceData[1]
    const graphElementId = getGraphElementId(study, gene)
    // Check that the ID exists on the page to avoid errors in corner cases where users update search terms quickly
    // or are toggling between study and gene view.
    if (document.getElementById(graphElementId)) {
      plot(graphElementId, expressionData, expressionLayout)
    }
  }

  /** gets expression data from the server */
  async function loadData(paramsToRender) {
    setIsLoading(true)

    const results = await fetchExpressionViolin(study.accession,
      gene,
      paramsToRender.cluster,
      paramsToRender.annotation,
      paramsToRender.subsample)

    setIsLoaded(true)
    setIsLoading(false)
    setClusterOptions(results.options)
    setAnnotationOptions(results.cluster_annotations)
    setSubsamplingOptions(results.subsampling_options)

    setRenderParams({
      userUpdated: false,
      cluster: results.rendered_cluster,
      annotation: results.rendered_annotation,
      subsample: results.rendered_subsample
    })

    parseAndPlot(results)
  }

  useEffect(() => {
    // do a load from the server if this is the initial load or if parameters
    // have been updated by the user.  Note we need the extra check because the
    // renderParams will actually change after the first server load as the
    // server sends back the option lists and selected defaults
    if (!isLoading && !isLoaded || renderParams.userUpdated) {
      loadData(renderParams)
    }
  }, [renderParams.cluster, renderParams.annotation, renderParams.subsample])

  return (
    <div className="row">
      <div className="col-md-10">
        <div
          className="expression-graph"
          id={ getGraphElementId(study, gene) }
          data-testid={ getGraphElementId(study, gene) }
        >
        </div>
        {
          isLoading &&
          <FontAwesomeIcon
            icon={faDna}
            data-testid={ `${getGraphElementId(study, gene)}-loading-icon` }
            className="gene-load-spinner"
          />
        }
        <span className="gene-title">{gene}</span>
      </div>
      <div className="col-md-2 graph-controls">
        <div className="form-group">
          <label>Load cluster</label>
          <select className="form-control cluster-select global-gene-cluster"
            value={renderParams.cluster}
            onChange={event => {
              updateRenderParams({ cluster: event.target.value })
            }
            }>
            { clusterOptions.map((opt, index) => {
              return <option key={index} value={opt}>{opt}</option>
            })}
          </select>
        </div>
        <div className="form-group">
          <label>Select annotation</label>
          <select
            className="form-control annotation-select global-gene-annotation"
            value={renderParams.annotation}
            onChange={event => {
              updateRenderParams({ annotation: event.target.value })
            }}>
            <optgroup label="Study Wide">
              { annotationOptions['Study Wide'].map((opt, index) => {
                return <option key={index} value={opt[1]}>{opt[0]}</option>
              })}
            </optgroup>
            <optgroup label="Cluster-Based">
              { annotationOptions['Cluster-Based'].map((opt, index) => {
                return <option key={index} value={opt[1]}>{opt[0]}</option>
              })}
            </optgroup>
          </select>
        </div>

        <div className="form-group">
          <label>Subsampling threshold</label>
          <select
            className="form-control subsample-select global-gene-subsample"
            onChange={event => {
              updateRenderParams({ subsample: event.target.value })
            }
            }>
            <option key={999} value=''>All cells</option>
            { subsamplingOptions.map((opt, index) => {
              return <option key={index} value={opt}>{opt}</option>
            })}
          </select>
        </div>
      </div>
    </div>
  )
}
