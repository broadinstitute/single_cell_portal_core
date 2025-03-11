import React, { useState, useEffect } from 'react'
import { manageDrawPathway, colorPathwayGenesByExpression } from '~/lib/pathway-expression'
// import { getPathwayName, getPathwayIdsByName } from '~/lib/search-utils'
import { getIdentifierForAnnotation } from '~/lib/cluster-utils'
import PlotUtils from '~/lib/plot'

import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faInfoCircle } from '@fortawesome/free-solid-svg-icons'

/** Get legend component for percent of cells expressng, for dot plot */
function PercentExpressingLegend() {
  return (
    <div className="percent-bars">
      <div className="percent-bar red-bar"></div>
      <div className="percent-bar blue-bar"></div>
      <div className="percent-labels">
        <span>0</span><span>38</span><span>75</span>
      </div>
      <div className="label">% expressing</div>
    </div>
  )
}

/** Get average expression legend for pathway diagram */
function ScaledMeanExpressionLegend() {
  return (
    <>
      <span>Scaled mean expression &nbsp;</span>
      <FontAwesomeIcon className="action help-icon" icon={faInfoCircle} />
      <div className="gradient-bar"></div>
      <div className="tick">
        <span>0</span><span>0.5</span><span>1</span>
      </div>
    </>
  )
}

/** Rearrange description from below diagram to right of diagram */
function moveDescription() {
  console.log('in moveDescription')
  const description = document.querySelector('.pathway-description')
  const footer = document.querySelector('._ideoPathwayFooter')

  if (footer) {
    description.innerHTML = ''
    description.insertAdjacentElement('beforeend', footer)
  }
}

/** Draw a pathway diagram with an expression overlay */
export default function Pathway({
  studyAccession, cluster, annotation, label, pathway, dimensions
}) {

  console.log('in Pathway, label', label)
  const pathwayId = pathway
  const pwDimensions = Object.assign({}, dimensions)

  pwDimensions.height -= 20
  pwDimensions.width -= 300

  manageDrawPathway(studyAccession, cluster, annotation, label)

  // Stringify object, to enable tracking state change
  const annotationId = getIdentifierForAnnotation(annotation)

  document.removeEventListener('ideogramDrawPathway', moveDescription)
  document.addEventListener('ideogramDrawPathway', moveDescription)

  useEffect(() => {
    window.Ideogram.drawPathway(pathwayId, '', '', '.pathway-diagram', pwDimensions, false)
  }, [cluster, annotationId, pathway])

  useEffect(() => {
    const dotPlotMetrics = window.SCP.dotPlotMetrics
    console.log('in Pathway label useEffect, dotPlotMetrics', dotPlotMetrics)
    if (!dotPlotMetrics) {return}
    colorPathwayGenesByExpression(label, dotPlotMetrics)
  }, [label])

  const diagramHeight = pwDimensions.height
  const pathwayDescriptionHeight = 500

  const diagramStyle = {
    height: diagramHeight + pathwayDescriptionHeight
  }

  const legendStyle = {
    height: '200px'
  }

  const scaledMeanHelpText =
    'Scaling is relative to each gene\'s expression across all cells in this ' +
    'annotation, i.e. cells associated with each annotation group.'

  return (
    <>
      <div className="pathway-diagram col-md-8" style={diagramStyle}></div>
      <div className="pathway-info-container col-md-3-5" style={{ float: 'right', marginRight: '10px' }}>
        <ScaledMeanExpressionLegend />
        <PercentExpressingLegend />
        <div className="pathway-description"></div>
      </div>
    </>
  )
}
