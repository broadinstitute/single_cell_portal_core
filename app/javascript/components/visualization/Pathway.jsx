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
  const pathwayDescriptionHeight = 600

  const diagramStyle = {
    width: pwDimensions.width,
    height: diagramHeight + pathwayDescriptionHeight,
    position: 'absolute'
  }

  const legendStyle = {
    float: 'right',
    width: '350px',
    marginRight: '50px'
  }

  return (
    <>
      <div className="pathway" style={diagramStyle}></div>
      <svg className="pathway-legend-container" style={legendStyle}>
        <ScaledMeanExpressionLegend />
      </svg>
    </>
  )
}
