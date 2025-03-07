import React, { useState, useEffect } from 'react'
import { manageDrawPathway } from '~/lib/pathway-expression'
// import { getPathwayName, getPathwayIdsByName } from '~/lib/search-utils'
import { getIdentifierForAnnotation } from '~/lib/cluster-utils'
import { ScaledMeanExpressionLegend } from '~/components/visualization/DotPlotLegend'
import PlotUtils from '~/lib/plot'
const { dotPlotColorScheme } = PlotUtils
import _uniqueId from 'lodash/uniqueId'

import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faInfoCircle } from '@fortawesome/free-solid-svg-icons'

const numberYPos = 30
const labelTextYPos = 52

/** Rectangle with color gradient for "Percent expressing" pathway overlay legend */
function GradientRect({color}) {
  const gradientId = _uniqueId('pathwayPercentExpressingGradient-')

  const colors = ['blue', 'purple', 'red']
  const i = colors.indexOf(color)
  const hexColor = dotPlotColorScheme.colors[i]

  console.log('i', i, 'color', color)

  return (
    <>
      <linearGradient id={gradientId} x1="0%" y1="0%" x2="100%" y2="0%">
        <stop offset="0%" stopColor="#FFF" key={1}/>
        <stop offset="100%" stopColor={hexColor} key={2}/>
      </linearGradient>
      <rect stroke="#AAA" fill={`url(#${gradientId})`} width="100" y={`${i * 14}`} height="10" rx="6" />
    </>
  )
}

// /** Get legend component for percent of cells expressng, for dot plot */
// function PercentExpressingLegend() {
//   return (
//     <g
//       className="pathway-legend-percent-expressing"
//       transform="translate(100,80)"
//     >
//       <GradientRect color="red" />
//       <GradientRect color="purple" />
//       <GradientRect color="blue" />
//       <g transform="translate(0, 30)">
//         <text x="12" y={numberYPos}>0</text>
//         <text x="45" y={numberYPos}>38</text>
//         <text x="78" y={numberYPos}>75</text>
//         <text x="10" y={labelTextYPos}>% expressing</text>
//       </g>
//     </g>
//   )
// }

/** Get legend component for percent of cells expressng, for dot plot */
function PercentExpressingLegend() {

  // const percentBarsStyle = { marginTop: '20px' }
  // const percentBarStyle = {
  //   width: '100px',
  //   height: '10px',
  //   borderRadius: '6px',
  //   border: '1px solid #AAA'
  // }
  // const redStyle = {background: 'linear-gradient(to right, #FFF, #FF0000)'}
  // const purpleStyle = {background: 'linear-gradient(to right, #FFF, #CC0088)'}
  // const blueStyle = {background: 'linear-gradient(to right, #FFF, #0000BB)'}

  // const percentLabelsStyle = {
  //   display: 'flex',
  //   justifyContent: 'space-between',
  //   width: '100px',
  //   fontSize: '12px',
  //   marginTop: '5px'
  // }

  return (
    <div className="percent-bars">
      <div className="percent-bar bar-1"></div>
      <div className="percent-bar bar-2"></div>
      <div className="percent-bar bar-3"></div>
      <div className="percent-labels">
        <span>0</span><span>38</span><span>75</span>
      </div>
      <div className="label">% expressing</div>
    </div>
  )
}

/** Get average expression legend for pathway diagram */
function PathwayScaledMeanExpressionLegend() {
  const gradientBarStyle = {
    width: '100px',
    height: '14px',
    borderRadius: '3px',
    background: 'linear-gradient(to right, #0000BB, #CC0088, #FF0000)'
  }

  const tickStyle = {
    display: 'flex',
    justifyContent: 'space-between',
    width: '100px'
  }

  return (
    <>
      <span>Scaled mean expression &nbsp;</span>
      <FontAwesomeIcon className="action help-icon" icon={faInfoCircle} />
      <div className="gradient-bar" style={gradientBarStyle}></div>
      <div className="tick" style={tickStyle}>
        <span>0</span><span>0.5</span><span>1</span>
      </div>
    </>
  )
}

/** Rearrange description from below diagram to right of diagram */
function moveDescription() {
  const description = document.querySelector('._ideoPathwayFooter')
  const infoContainer = document.querySelector('.pathway-info-container')
  infoContainer.insertAdjacentElement('beforeend', description)
}

/** Draw a pathway diagram with an expression overlay */
export default function Pathway({
  studyAccession, cluster, annotation, pathway, dimensions
}) {
  const pathwayId = pathway
  const pwDimensions = Object.assign({}, dimensions)

  pwDimensions.height -= 20
  pwDimensions.width -= 300

  manageDrawPathway(studyAccession, cluster, annotation)

  // Stringify object, to enable tracking state change
  const annotationId = getIdentifierForAnnotation(annotation)

  document.removeEventListener('ideogramDrawPathway', moveDescription)
  document.addEventListener('ideogramDrawPathway', moveDescription)

  useEffect(() => {
    window.Ideogram.drawPathway(pathwayId, '', '', '.pathway-diagram', pwDimensions, false)
  }, [cluster, annotationId, pathway])

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
      <div className="pathway-info-container col-md-3" style={{ float: 'right' }}>
        <PathwayScaledMeanExpressionLegend />
        <PercentExpressingLegend />
      </div>
    </>
  )
}
