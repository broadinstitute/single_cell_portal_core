import React, { useState, useEffect } from 'react'
import { manageDrawPathway } from '~/lib/pathway-expression'
// import { getPathwayName, getPathwayIdsByName } from '~/lib/search-utils'
import { getIdentifierForAnnotation } from '~/lib/cluster-utils'
import { ScaledMeanExpressionLegend } from '~/components/visualization/DotPlotLegend'

/**  */
export default function Pathway({
  studyAccession, cluster, annotation, pathway, dimensions
}) {
  const pathwayId = pathway
  const pwDimensions = Object.assign({}, dimensions)

  pwDimensions.height -= 80
  pwDimensions.width -= 200

  manageDrawPathway(studyAccession, cluster, annotation)

  // Stringify object, to enable tracking state change
  const annotationId = getIdentifierForAnnotation(annotation)

  useEffect(() => {
    window.Ideogram.drawPathway(pathwayId, '', '', '.pathway', pwDimensions, false)
  }, [cluster, annotationId, pathway])

  const diagramHeight = pwDimensions.height
  const pathwayDescriptionHeight = 500

  const diagramStyle = {
    height: diagramHeight + pathwayDescriptionHeight
  }

  const legendStyle = {
    // float: 'right',
    // width: '350px',
    // marginRight: '50px'
  }

  const scaledMeanHelpText =
    'Scaling is relative to each gene\'s expression across all cells in this ' +
    'annotation, i.e. cells associated with each annotation group.'

  return (
    <>
      <div className="pathway col-md-8" style={diagramStyle}></div>
      <div className="pathway-legend-container col-md-3" style={{float: 'right'}}>
        <svg style={legendStyle}>
          <ScaledMeanExpressionLegend
            helpText={scaledMeanHelpText}
            horizontalTransform=''
            verticalTransform='up-3'
            popoverPlacement='bottom'
            translateX='100'
          />
        </svg>
      </div>
    </>
  )
}
