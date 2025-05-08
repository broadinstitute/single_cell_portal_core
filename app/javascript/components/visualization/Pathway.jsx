import React, { useState, useEffect } from 'react'
import { Popover, OverlayTrigger } from 'react-bootstrap'
import { manageDrawPathway, writeLoadingIndicator } from '~/lib/pathway-expression'
import { getIdentifierForAnnotation, naturalSort } from '~/lib/cluster-utils'
import { round } from '~/lib/metrics-perf'
import { log } from '~/lib/metrics-api'

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

  const pathwayId = window.Ideogram.pathwayJson.pathway.id
  const pathwayName = window.Ideogram.pathwayJson.pathway.name

  log('pathway-node-tooltip', {
    pathway: pathwayId,
    pathwayName,
    nodeName: geneName,
    nodeType: 'gene'
  })

  return ''
}

/**
 * Set up tippy tooltips for pathway-type nodes within the pathway diagram
 *
 * Pathway diagrams contain various node types, e.g. for genes, metabolites,
 * and pathways.  Pathway-type nodes are how pathway diagrams link to each
 * other.
 */
function configurePathwayTooltips() {
  document.querySelectorAll('g.Pathway').forEach(node => {
    node.setAttribute('data-toggle', 'tooltip')
    node.setAttribute('data-html', 'true')
    node.setAttribute('data-original-title', 'Click for expression in pathway')
  })

  document.querySelector('#_ideogramPathwayContainer').style.zIndex = ''
}

/** Draw a pathway diagram with an expression overlay */
export default function Pathway({
  studyAccession, cluster, annotation, label, pathway, dimensions,
  labels, queryFn
}) {
  const [geneList, setGeneList] = useState([])
  const [cellTypes, setCellTypes] = useState('')
  const [diseases, setDiseases] = useState('')

  const pathwayId = pathway
  const pwDimensions = Object.assign({}, dimensions)

  pwDimensions.height -= 20
  pwDimensions.width -= 300

  if (label === '') {
    label = labels[0]
  }

  // Stringify object, to enable tracking state change
  const annotationId = getIdentifierForAnnotation(annotation)

  /** Set "Cell types" and "Diseases" pathway ontology annotations */
  function updatePathwayOntologies() {
    const pathwayJson = window.Ideogram.pathwayJson
    let newCellTypes = window.Ideogram.getPathwayOntologies(pathwayJson, 'cell type')
    newCellTypes = newCellTypes.replace('Cell type: ', '')
    setCellTypes(newCellTypes)
    let newDiseases = window.Ideogram.getPathwayOntologies(pathwayJson, 'disease')
    newDiseases = newDiseases.replace('Disease: ', '')
    setDiseases(newDiseases)
  }

  moveDescription()
  document.addEventListener('ideogramDrawPathway', configurePathwayTooltips)
  document.addEventListener('ideogramDrawPathway', updatePathwayOntologies)
  document.addEventListener('ideogramDrawPathway', writeLoadingIndicator)

  /** Upon clicking a pathway node, show new pathway and expression overlay */
  function handlePathwayNodeClick(event, pathwayId) {
    queryFn([pathwayId])

    const pathwayName = window.Ideogram.pathwayJson.pathway.name

    log('pathway-node-click', {
      pathway: pathwayId,
      pathwayName,
      nodeType: 'pathway'
    })
  }

  const dimensionString = JSON.stringify(dimensions)

  const sourceGene = ''
  const destGene = ''
  const showClose = false
  const showDefaultTooltips = false
  const showPathwayOntologies = false

  useEffect(() => {
    manageDrawPathway(studyAccession, cluster, annotation, label, labels)
    const showDescription = false

    window.Ideogram.drawPathway(
      pathwayId, sourceGene, destGene, '.pathway-diagram', pwDimensions, showClose,
      handleGeneNodeHover, handlePathwayNodeClick,
      showDescription, showPathwayOntologies, showDefaultTooltips
    )
  }, [cluster, annotationId, dimensionString, label])

  useEffect(() => {
    manageDrawPathway(studyAccession, cluster, annotation, label, labels)

    const showDescription = true

    window.Ideogram.drawPathway(
      pathwayId, sourceGene, destGene, '.pathway-diagram', pwDimensions, showClose,
      handleGeneNodeHover, handlePathwayNodeClick,
      showDescription, showPathwayOntologies, showDefaultTooltips
    )
  }, [pathway])

  const diagramHeight = pwDimensions.height

  const diagramStyle = {
    height: diagramHeight
  }

  const descriptionPad = window.innerWidth <= 1300 ? 150 : 100
  const descriptionHeight = diagramHeight - descriptionPad

  const GeneListPopover =
    <Popover id="pathway-genes-popover">
      Genes in this pathway:
      <br/><br/>
      {naturalSort(geneList).join(', ')}
    </Popover>

  const CellTypesPopover =
    <Popover id="pathway-cell-types-popover">
      Cell types in this pathway:
      <br/><br/>
      <div
        dangerouslySetInnerHTML={{ __html: cellTypes }}
      />
    </Popover>

  const DiseasesPopover =
    <Popover id="pathway-cell-types-popover">
      Diseases in this pathway:
      <br/><br/>
      <div
        dangerouslySetInnerHTML={{ __html: diseases }}
      />
    </Popover>

  return (
    <>
      <div className="pathway-diagram col-md-8" style={diagramStyle}></div>
      <div className="pathway-info-container col-md-3-5" style={{ float: 'right', marginRight: '10px' }}>
        <div className="pathway-overlay-legend">
          <ScaledMeanExpressionLegend />
          <PercentExpressingLegend />
        </div>
        <div className="pathway-description" style={{ height: descriptionHeight }}></div>
        <div
          className="pathway-more-details"
          style={{ height: '65px', borderTop: '1px solid #DDD' }}
        >
          <OverlayTrigger trigger={['click']} placement='top' rootClose={true}
            overlay={GeneListPopover}>
            <button
              className="btn terra-secondary-btn"
              style={{ marginTop: '10px' }}
              onClick={() => {
                setGeneList(window.Ideogram.getPathwayGenes)
              }}
            >Genes</button>
          </OverlayTrigger>
          {cellTypes.length > 0 &&
          <OverlayTrigger trigger={['click']} placement='top' rootClose={true}
            overlay={CellTypesPopover}>
            <button
              className="btn terra-secondary-btn"
              style={{ marginTop: '10px', marginLeft: '10px' }}
            >Cell types</button>
          </OverlayTrigger>
          }
          {diseases.length > 0 &&
          <OverlayTrigger trigger={['click']} placement='top' rootClose={true}
            overlay={DiseasesPopover}>
            <button
              className="btn terra-secondary-btn"
              style={{ marginTop: '10px', marginLeft: '10px' }}
            >Diseases</button>
          </OverlayTrigger>
          }
        </div>
      </div>
    </>
  )
}
