import React, { useState, useEffect } from 'react'
import { manageDrawPathway, renderPathwayExpression } from '~/lib/pathway-expression'
// import { getPathwayName, getPathwayIdsByName } from '~/lib/search-utils'
import { getIdentifierForAnnotation } from '~/lib/cluster-utils'
import PlotUtils from '~/lib/plot'
import { round } from '~/lib/metrics-perf'

import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faInfoCircle } from '@fortawesome/free-solid-svg-icons'

/** Get legend component for percent of cells expressng, for dot plot */
function PercentExpressingLegend() {
  return (
    <div className="percent-bars">
      <div className="percent-expressing-label">% expressing</div>
      <div className="percent-bar red-bar"></div>
      <div className="percent-bar blue-bar"></div>
      <div className="percent-labels">
        <span>0</span><span>38</span><span>75</span>
      </div>
    </div>
  )
}

/** Get average expression legend for pathway diagram */
function ScaledMeanExpressionLegend() {
  const scaledMeanHelpText =
    'Scaling is relative to each gene\'s expression across all cells in this ' +
    'annotation, i.e. cells associated with each annotation group.'

  return (
    <>
      <div className="scaled-mean-header">
        Scaled mean expression &nbsp;
        <FontAwesomeIcon
          className="action help-icon"
          icon={faInfoCircle}
          data-toggle="tooltip"
          data-original-title={scaledMeanHelpText}
        />
      </div>
      <div className="gradient-bar"></div>
      <div className="tick">
        <span>0</span><span>0.5</span><span>1</span>
      </div>
    </>
  )
}

/** Rearrange description from below diagram to right of diagram */
function moveDescription() {
  const description = document.querySelector('.pathway-description')
  const footer = document.querySelector('._ideoPathwayFooter')

  if (footer) {
    description.innerHTML = ''
    description.insertAdjacentElement('beforeend', footer)

    document.removeEventListener('ideogramDrawPathway', moveDescription)
  }
}

/** Draw a pathway diagram with an expression overlay */
export default function Pathway({
  studyAccession, cluster, annotation, label, pathway, dimensions,
  labels
}) {
  const pathwayId = pathway
  const pwDimensions = Object.assign({}, dimensions)

  pwDimensions.height -= 20
  pwDimensions.width -= 300

  if (label === '') {
    label = labels[0]
  }

  // Stringify object, to enable tracking state change
  const annotationId = getIdentifierForAnnotation(annotation)

  const dimensionString = JSON.stringify(dimensions)

  moveDescription()

  /** Prepare gene-specific content for node hover tooltip */
  function handleNodeHover(event, geneName) {
    const node = event.target
    const rawMean = node.getAttribute('data-scaled-mean-expression');
    const mean = round(rawMean, 2)
    const rawPercent = node.getAttribute('data-percent-expressing');
    const percent = round(rawPercent, 2)
    const content =
      `
      <div style="padding: 5px;">
        <div>Metrics for gene ${geneName} in ${label}:</div>
        <div>Scaled mean expression asdf: ${mean}</div>
        <div>Percent of cells expressing: ${percent}</div>
      </div>
      `
    return content
  }

  useEffect(() => {
    manageDrawPathway(studyAccession, cluster, annotation, label, labels)
    window.Ideogram.drawPathway(
      pathwayId, '', '', '.pathway-diagram', pwDimensions, false,
      handleNodeHover
    )
  }, [cluster, annotationId, pathway, dimensionString])

  useEffect(() => {
    renderPathwayExpression(studyAccession, cluster, annotation, label, labels)
  }, [label])

  const diagramHeight = pwDimensions.height

  const diagramStyle = {
    height: diagramHeight
  }

  return (
    <>
      <div className="pathway-diagram col-md-8" style={diagramStyle}></div>
      <div className="pathway-info-container col-md-3-5" style={{ float: 'right', marginRight: '10px' }}>
        <div className="pathway-overlay-legend">
          <ScaledMeanExpressionLegend />
          <PercentExpressingLegend />
        </div>
        <div className="pathway-description" style={{ height: diagramHeight - 65 }}></div>
        <div style={{ height: 30, background: 'red' }}></div>
      </div>
    </>
  )
}
