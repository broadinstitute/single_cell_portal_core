import React, { useState, useEffect } from 'react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faDna } from '@fortawesome/free-solid-svg-icons'
import _uniqueId from 'lodash/uniqueId'
import _capitalize from 'lodash/capitalize'
import { fetchExpressionViolin } from 'lib/scp-api'
import { getColorBrewerColor, arrayMin, arrayMax, plotlyDefaultLineColor } from 'lib/plot'
import Plotly from 'plotly.js-dist'

import { useUpdateEffect, useUpdateLayoutEffect } from 'hooks/useUpdate'


export const DISTRIBUTION_PLOT_OPTIONS = [
  { label: 'Violin plot', value: 'violin' },
  { label: 'Box plot', value: 'box' }
]
export const defaultDistributionPlot = DISTRIBUTION_PLOT_OPTIONS[0].value

export const DISTRIBUTION_POINTS_OPTIONS = [
  { label: 'None', value: 'none' },
  { label: 'All', value: 'all' },
  { label: 'Outliers', value: 'outliers' },
  { label: 'Suspected outliers', value: 'suspectedoutliers' }
]
export const defaultDistributionPoints = DISTRIBUTION_POINTS_OPTIONS[0].value

/** displays a violin plot of expression data for the given gene and study
 * @param studyAccession {String} the study accession
 * @param genes {Array[String]} array of gene names
 * @param cluster {string} the name of the cluster, or blank/null for the study's default
 * @param annotation {obj} an object with name, type, and scope attributes
 * @param subsample {string} a string for the subsampel to be retrieved.
 * @param consensus {string} for multi-gene expression plots
 * @param distributionPlot {string} 'box' or 'violin' for the plot type (default is violin)
 * @param distributionPoints {string} 'none' 'all' 'suspectedoutliers' or 'outliers'
 * @param setAnnotationList {function} for global gene search and other places where a single call is used to
 *   fetch both the default expression data and the cluster menu options, a function that will be
 *   called with the annotationList returned by that call.
  */
export default function StudyViolinPlot({
  studyAccession, genes, cluster, annotation, subsample, consensus, distributionPlot, distributionPoints,
  updateDistributionPlot, setAnnotationList, dimensions
}) {
  const [isLoading, setIsLoading] = useState(false)
  // array of gene names as they are listed in the study itself
  const [studyGeneNames, setStudyGeneNames] = useState([])
  const [graphElementId] = useState(_uniqueId('study-violin-'))

  /** gets expression data from the server */
  async function loadData() {
    setIsLoading(true)
    const results = await fetchExpressionViolin(
      studyAccession,
      genes,
      cluster,
      annotation.name,
      annotation.type,
      annotation.scope,
      subsample,
      consensus
    )
    setIsLoading(false)
    setStudyGeneNames(results.gene_names)

    let distributionPlotToUse = results.plotType
    if (distributionPlot) {
      distributionPlotToUse = distributionPlot
    }
    if (!distributionPlotToUse) {
      distributionPlotToUse = defaultDistributionPlot
    }
    renderViolinPlot(graphElementId, results, {
      plotType: distributionPlotToUse,
      showPoints: distributionPoints
    })
    if (setAnnotationList) {
      setAnnotationList(results.annotation_list)
    }
    if (updateDistributionPlot) {
      updateDistributionPlot(distributionPlotToUse)
    }
  }
  /** handles fetching the expression data (and menu option data) from the server */
  useEffect(() => {
    loadData()
  }, [ // do a load from the server if any of the paramenters passed to fetchExpressionViolin have changed
    studyAccession,
    genes[0],
    cluster,
    annotation.name,
    annotation.scope,
    subsample,
    consensus
  ])

  // useEffect for handling render param re-renders
  useUpdateEffect(() => {
    // Don't try to update the if the data hasn't loaded yet
    if (!isLoading && studyGeneNames.length > 0) {
      updateViolinPlot(graphElementId, distributionPlot, distributionPoints)
    }
  }, [distributionPlot, distributionPoints])

  // Adjusts width and height of plots upon toggle of "View Options"
  useUpdateEffect(() => {
    // Don't update if the graph hasn't loaded yet
    if (!isLoading && studyGeneNames.length > 0) {
      const { width, height } = dimensions
      const layoutUpdate = { width, height }
      Plotly.relayout(graphElementId, layoutUpdate)
    }
  }, [dimensions.width, dimensions.height])

  const isCollapsedView = ['mean', 'median'].indexOf(consensus) >= 0
  return (
    <div className="plot">
      <div
        className="expression-graph"
        id={graphElementId}
        data-testid={graphElementId}
      >
      </div>
      {
        isLoading &&
        <FontAwesomeIcon
          icon={faDna}
          data-testid={`${graphElementId}-loading-icon`}
          className="gene-load-spinner"
        />
      }
      {/* we have to explicitly test length > 0 below, just asserting .length would
       sometimes render a zero to the page*/}
      { isCollapsedView && studyGeneNames.length > 0 &&
        <div className="text-center">
          <span>{_capitalize(consensus)} expression of {studyGeneNames.join(', ')}</span>
        </div>
      }
    </div>
  )
}


/** Formats expression data for Plotly, draws violin (or box) plot */
function renderViolinPlot(target, results, { plotType, showPoints }) {
  const traceData = getViolinTraces(results.values, showPoints, plotType)
  const layout = getViolinLayout(results.rendered_cluster, results.y_axis_title)
  Plotly.newPlot(target, traceData, layout)
}

/** changes visual style of the plot without re-fetching data */
function updateViolinPlot(target, plotType, showPoints) {
  const existingData = document.getElementById(target).data.reduce((map, obj) => {
    map[obj.name] = obj
    return map
  }, {})
  const traceData = getViolinTraces(existingData, showPoints, plotType)
  Plotly.react(target, traceData, target.layout)
}

/**
 * Creates Plotly traces and layout for violin plots and box plots
 *
 * takes a 'values' object which should correspond to the 'values' field of a call
 * to expression_controller/violin.  { <name>: { y: [<<data>>]}}
*/
function getViolinTraces(
  resultValues, showPoints='none', plotType='violin'
) {
  const data = Object.entries(resultValues).map(([traceName, traceData], index) => {
    // Plotly violin trace creation, adding to master array
    // get inputs for plotly violin creation
    const dist = traceData.y

    // Replace the none selection with bool false for plotly
    if (showPoints === 'none' || !showPoints) {
      showPoints = false
    }

    // Check if there is a distribution before adding trace
    if (arrayMax(dist) !== arrayMin(dist) && plotType === 'violin') {
      // Make a violin plot if there is a distribution
      return {
        type: 'violin',
        name: traceName,
        y: dist,
        points: showPoints,
        pointpos: 0,
        jitter: 0.85,
        spanmode: 'hard',
        box: {
          visible: true,
          fillcolor: '#ffffff',
          width: .1
        },
        marker: {
          size: 2,
          color: '#000000',
          opacity: 0.8
        },
        fillcolor: getColorBrewerColor(index),
        line: {
          color: '#000000',
          width: 1.5
        },
        meanline: {
          visible: false
        }
      }
    } else {
      // Make a boxplot for data with no distribution
      return {
        type: 'box',
        name: traceName,
        y: dist,
        boxpoints: showPoints,
        marker: {
          color: getColorBrewerColor(index),
          size: 2,
          line: {
            color: plotlyDefaultLineColor
          }
        },
        boxmean: true
      }
    }
  })
  return data
}

/** Get Plotly layout for violin plot */
function getViolinLayout(title, expressionLabel) {
  return {
    title,
    // Force axis labels, including number strings, to be treated as
    // categories.  See Python docs (same generic API as JavaScript):
    // https://plotly.com/python/axes/#forcing-an-axis-to-be-categorical
    // Relevant Plotly JS example:
    // https://plotly.com/javascript/axes/#categorical-axes
    xaxis: {
      type: 'category'
    },
    yaxis: {
      zeroline: true,
      showline: true,
      title: expressionLabel
    },
    margin: {
      pad: 10,
      b: 100
    },
    autosize: true
  }
}
