import React, { useState, useEffect, useRef } from 'react'
import _uniqueId from 'lodash/uniqueId'

import { log } from '~/lib/metrics-api'
import { renderHeatmap, refitHeatmap } from '~/lib/morpheus-heatmap'
import { getExpressionHeatmapURL, getGeneListColsURL } from '~/lib/scp-api'
import { useUpdateEffect } from '~/hooks/useUpdate'
import useErrorMessage from '~/lib/error-message'
import { withErrorBoundary } from '~/lib/ErrorBoundary'
import LoadingSpinner from '~/lib/LoadingSpinner'


/** renders a morpheus powered heatmap for the given params
  * @param geneList {String} a string for the gene list (precomputed score) to be retrieved.
  * @param geneLists {Array} array of gene list information, such as returned by the explore_controller
 */
function RawGeneListHeatmap({
  studyAccession, geneList: geneListName,
  geneLists=[], heatmapFit, heatmapRowCentering
}) {
  const [graphId] = useState(_uniqueId('heatmap-'))
  const morpheusHeatmap = useRef(null)
  let expressionValuesURL = getExpressionHeatmapURL({
    studyAccession,
    heatmapRowCentering,
    geneList: geneListName
  })
  const { ErrorComponent, setShowError, setError } = useErrorMessage()
  // we can't render until we know what the cluster is, since morpheus requires the annotation name
  // so don't try until we've received this, unless we're showing a Gene List
  const canRender = !!geneListName && geneLists.length

  const geneListInfo = geneLists.find(gl => gl.name === geneListName)
  const description = geneListInfo?.description
  const annotationCellValuesURL = getGeneListColsURL({ studyAccession, geneList: geneListName })
  const isCustomScaling = heatmapRowCentering === true || heatmapRowCentering === 'true'
  const colorMin = isCustomScaling ? geneListInfo.heatmap_file_info?.color_min : null
  const colorMax = isCustomScaling ? geneListInfo.heatmap_file_info?.color_max : null
  // For baffling reasons, morpheus will not render a geneList heatmap correctly unless
  // there is another parameter on the query string. Despite the fact that I've confirmed the
  // server responses are identical with/without the extra param.
  expressionValuesURL = `${expressionValuesURL}&z=1`

  useEffect(() => {
    performance.mark(`perfTimeStart-${graphId}`)

    log('heatmap:initialize')
    setShowError(false)
    morpheusHeatmap.current = renderHeatmap({
      target: `#${graphId}`,
      expressionValuesURL,
      annotationCellValuesURL,
      annotationName: geneListName,
      fit: heatmapFit,
      rowCentering: heatmapRowCentering,
      sortColumns: false,
      setShowError,
      setError,
      colorMin,
      colorMax
    })
  }, [
    studyAccession,
    heatmapRowCentering,
    geneListName
  ])

  useUpdateEffect(() => {
    refitHeatmap(morpheusHeatmap?.current, heatmapFit)
  }, [heatmapFit])


  return (
    <div>
      <div>
        <h5 className="text-center heatmap-title">{geneListName}</h5>
        <div className="text-center">{ description }</div>
      </div>
      <div className="plot">
        { ErrorComponent }
        <LoadingSpinner isLoading={!canRender}>
          <div id={graphId} className="heatmap-graph" style={{ minWidth: '80vw' }}></div>
        </LoadingSpinner>
      </div>

    </div>
  )
}


const GeneListHeatmap = withErrorBoundary(RawGeneListHeatmap)
export default GeneListHeatmap

