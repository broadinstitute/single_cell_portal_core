import React, { useState, useEffect, useRef } from 'react'
import _uniqueId from 'lodash/uniqueId'

import { log } from '~/lib/metrics-api'
import { getExpressionHeatmapURL, getAnnotationCellValuesURL, fetchMorpheusJson } from '~/lib/scp-api'

import { useUpdateEffect } from '~/hooks/useUpdate'
import useErrorMessage from '~/lib/error-message'
import { renderHeatmap, refitHeatmap } from '~/lib/morpheus-heatmap'
import { withErrorBoundary } from '~/lib/ErrorBoundary'
import LoadingSpinner, { morpheusLoadingSpinner } from '~/lib/LoadingSpinner'


/** renders a morpheus powered heatmap for the given params
  * @param genes {Array[String]} array of gene names
  * @param cluster {string} the name of the cluster, or blank/null for the study's default
  * @param annotation {obj} an object with name, type, and scope attributes
  * @param subsample {string} a string for the subsampel to be retrieved.
  * @param morpheusData {object} JSON Morpheus dataset
 */
function RawHeatmap({
  studyAccession, genes=[], cluster, annotation={}, subsample, heatmapFit, heatmapRowCentering,
  morpheusData
}) {
  const [graphId] = useState(_uniqueId('heatmap-'))
  const morpheusHeatmap = useRef(null)
  const { ErrorComponent, setShowError, setErrorContent } = useErrorMessage()
  // we can't render until we know what the cluster is, since morpheus requires the annotation name
  // so don't try until we've received this, unless we're showing a Gene List
  const canRender = !!cluster && !!morpheusData

  useEffect(() => {
    if (canRender) {
      const target = `#${graphId}`
      $(target).empty()
      $(target).html(morpheusLoadingSpinner())
      performance.mark(`perfTimeStart-${graphId}`)
      log('heatmap:initialize')
      setShowError(false)
      morpheusHeatmap.current = renderHeatmap({
        target,
        dataset: morpheusData,
        annotationCellValuesURL: '',
        annotationName: annotation.name,
        fit: heatmapFit,
        rowCentering: heatmapRowCentering,
        sortColumns: true,
        setShowError,
        setErrorContent,
        genes
      })
    }
  }, [
    studyAccession,
    genes.join(','),
    morpheusData,
    cluster,
    annotation.name,
    annotation.scope,
    heatmapRowCentering
  ])

  useUpdateEffect(() => {
    refitHeatmap(morpheusHeatmap?.current, heatmapFit)
  }, [heatmapFit])

  return (
    <div>
      <div className="plot">
        { ErrorComponent }
        <LoadingSpinner isLoading={!canRender}>
          <div id={graphId} className="heatmap-graph" style={{ minWidth: '80vw' }}></div>
        </LoadingSpinner>
      </div>
    </div>
  )
}

const Heatmap = withErrorBoundary(RawHeatmap)
export default Heatmap
