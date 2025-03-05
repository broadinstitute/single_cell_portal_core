import React, { useState, useEffect } from 'react'
import { manageDrawPathway } from '~/lib/pathway-expression'
// import { getPathwayName, getPathwayIdsByName } from '~/lib/search-utils'
import { getIdentifierForAnnotation } from '~/lib/cluster-utils'
import { ScaledMeanExpressionLegend } from '~/components/visualization/DotPlotLegend'
import PlotUtils from '~/lib/plot'
const { dotPlotColorScheme } = PlotUtils
import _uniqueId from 'lodash/uniqueId'

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
      <rect stroke="#888" fill={`url(#${gradientId})`} width="100" y={`${i * 20}`} height="14" rx="10" />
    </>
  )
}

/** Get legend component for percent of cells expressng, for dot plot */
function PercentExpressingLegend() {
  return (
    <g
      className="pathway-legend-percent-expressing"
      transform="translate(90,80)"
    >
      <GradientRect color="red" />
      <GradientRect color="purple" />
      <GradientRect color="blue" />
      <circle cx="20" cy="8" r="1"/>
      <circle cx="57.5" cy="8" r="3"/>
      <circle cx="90" cy="8" r="7"/>
      <circle cx="57.5" cy="8" r="3"/>

      <text x="17" y={numberYPos}>0</text>
      <text x="50" y={numberYPos}>38</text>
      <text x="83" y={numberYPos}>75</text>

      <text x="15" y={labelTextYPos}>% expressing</text>
    </g>
  )
}

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
          <PercentExpressingLegend />
        </svg>
      </div>
    </>
  )
}
