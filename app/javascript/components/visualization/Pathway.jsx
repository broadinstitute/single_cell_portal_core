import React, { useState, useEffect } from 'react'
import { Popover, OverlayTrigger } from 'react-bootstrap'
import { manageDrawPathway } from '~/lib/pathway-expression'
import { getIdentifierForAnnotation, naturalSort } from '~/lib/cluster-utils'
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

/** Prepare gene-specific content for node hover tooltip */
function handleGeneNodeHover(event, geneName) {
  const node = event.target
  const rawMean = node.getAttribute('data-scaled-mean-expression')
  const mean = round(rawMean, 2)
  const rawPercent = node.getAttribute('data-percent-expressing')
  const percent = round(rawPercent, 2)
  const content =
    `
    <div>
      <div>Metrics for ${geneName}:</div>
      <div>Mean expression: ${mean}</div>
      <div>Percent of cells expressing: ${percent}</div>
      </ul>
    </div>
    `

  node.setAttribute('data-toggle', 'tooltip')
  node.setAttribute('data-html', 'true')
  node.setAttribute('data-original-title', content)
  return ''
}

/** Draw a pathway diagram with an expression overlay */
export default function Pathway({
  studyAccession, cluster, annotation, label, pathway, dimensions,
  labels, updateExploreParams
}) {
  const [geneList, setGeneList] = useState([])

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

  /** Upon clicking a pathway node, show new pathway and expression overlay */
  function handlePathwayNodeClick(event, pathwayId) {
    updateExploreParams({ pathway: pathwayId })
  }

  useEffect(() => {
    manageDrawPathway(studyAccession, cluster, annotation, label, labels)
    window.Ideogram.drawPathway(
      pathwayId, '', '', '.pathway-diagram', pwDimensions, false,
      handleGeneNodeHover, handlePathwayNodeClick
    )
  }, [cluster, annotationId, pathway, dimensionString, label])

  const diagramHeight = pwDimensions.height

  const diagramStyle = {
    height: diagramHeight
  }

  const GeneListPopover =
    <Popover data-analytics-name='gene-list-popover' id='gene-list-popover'>
      {naturalSort(geneList).join(', ')}
    </Popover>

  return (
    <>
      <div className="pathway-diagram col-md-8" style={diagramStyle}></div>
      <div className="pathway-info-container col-md-3-5" style={{ float: 'right', marginRight: '10px' }}>
        <div className="pathway-overlay-legend">
          <ScaledMeanExpressionLegend />
          <PercentExpressingLegend />
        </div>
        <div className="pathway-description" style={{ height: diagramHeight - 100 }}></div>
        <div
          className="pathway-more-details"
          style={{ height: '65px', borderTop: '1px solid #DDD' }}
          onClick={() => {
            setGeneList(window.Ideogram.getPathwayGenes)
          }}
        >
          <OverlayTrigger trigger={['click']} placement='top' rootClose={true}
            overlay={GeneListPopover}>
            <button className="btn terra-secondary-btn" style={{ marginTop: '10px' }}>Gene list</button>
          </OverlayTrigger>
        </div>
      </div>
    </>
  )
}
