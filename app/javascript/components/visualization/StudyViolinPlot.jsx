import React, { useState, useEffect } from 'react'
import _uniqueId from 'lodash/uniqueId'
import Plotly from 'plotly.js-dist'
import { fetchCluster } from '~/lib/scp-api'

import { fetchExpressionViolin } from '~/lib/scp-api'
import PlotUtils from '~/lib/plot'
const {
  getColorBrewerColor, arrayMin, arrayMax, plotlyDefaultLineColor,
  DISTRIBUTION_PLOT_OPTIONS, defaultDistributionPlot, DISTRIBUTION_POINTS_OPTIONS, defaultDistributionPoints
} = PlotUtils
import { useUpdateEffect } from '~/hooks/useUpdate'
import { withErrorBoundary } from '~/lib/ErrorBoundary'
import useErrorMessage from '~/lib/error-message'
import { logViolinPlot } from '~/lib/scp-api-metrics'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { formatGeneList } from '~/components/visualization/PlotTitle'

/** Title for violin plot; also accounts for "Collapsed by" / consensus view */
function ViolinPlotTitle({ cluster, annotation, genes, consensus }) {
  const isCollapsedView = ['mean', 'median'].includes(consensus)

  const title = formatGeneList(genes)

  // We need to explicitly test length > 0 below, just asserting .length would
  // sometimes render a zero to the page
  if (isCollapsedView && genes.length > 0) {
    title.push(<span key="c"> {consensus}</span>)
  }
  title.push(<span key="e"> expression in <i>{cluster}</i> by <b>{annotation}</b></span>)


  return (
    <h5 className="plot-title violin-title">{title}</h5>
  )
}

window.SCP.violinCellIndexes = {}

/** Web worker that wraps a CPU-intensive function */
function setViolinCellIndexesWorker() {
  /**
   * Set an index to apply cell filtering for this gene in violin plots.
   *
   * This is done 1 time per gene. It is a CPU-intensive function, so it
   * is processed in a non-main thread.
   */
  function setViolinCellIndexes(results, allCellNames) {
    const violinCellIndexes = {}
    Object.keys(results.values).forEach(group => {
      violinCellIndexes[group] = []
      const cellNames = results.values[group].cells
      for (let i = 0; i < cellNames.length; i++) {
        const cellName = cellNames[i]
        const cellIndex = allCellNames.indexOf(cellName)
        violinCellIndexes[group].push(cellIndex)
      }
    })
    return violinCellIndexes
  }

  // Set up message handling for web worker
  self.onmessage = function(event) {
    const [gene, results, allCellNames] = event.data

    const violinCellIndexes = setViolinCellIndexes(results, allCellNames)

    self.postMessage(
      [gene, violinCellIndexes]
    )
  }
}

/** Compute violin cell indexes, and wait for that to finish */
async function workSetViolinCellIndexes(gene, results, allCellNames) {
  window.SCP.workers.violin.postMessage([gene, results, allCellNames])

  await new Promise(resolve => {
    /** Poll for gene in violinCellIndexes */
    function pollForIndex() {
      setTimeout(() => {
        if (gene in window.SCP.violinCellIndexes === false) {
          return pollForIndex()
        } else {
          resolve()
        }
      }, 50)
    }
    pollForIndex()
  })
}

// Build a worker from an anonymous function body, and enable worker to be
// initialized without a network request.
//
// Web workers like this enable CPU-intensive tasks to be done off the main
// (i.e., UI) thread, which keeps the UX responsive while non-trivial work is
// done in the browser.
const blobURL = URL.createObjectURL(new Blob(['(',
  setViolinCellIndexesWorker.toString(),
  ')()'], { type: 'application/javascript' }))

window.SCP.workers = {}

window.SCP.workers.violin = new Worker(blobURL)

window.SCP.workers.violin.onmessage = function(event) {
  const [gene, violinCellIndexes] = event.data
  window.SCP.violinCellIndexes[gene] = violinCellIndexes
}

// We don't need this after creating the worker
URL.revokeObjectURL(blobURL)

/** Get array of names for all cells in clustering */
async function getAllCellNames(studyAccession, cluster, annotation) {
  const clusterData = await fetchCluster({
    studyAccession, cluster, annotation, subsample: 'All'
  })
  const allCellNames = clusterData[0].data.cells
  return allCellNames
}

/** Filter cells in violin plot */
async function filterResults(
  studyAccession, cluster, annotation, gene,
  results, cellFaceting, filteredCells
) {
  if (gene in window.SCP.violinCellIndexes === false) {
    const allCellNames = await getAllCellNames(studyAccession, cluster, annotation)
    await workSetViolinCellIndexes(gene, results, allCellNames)
  }

  if (!filteredCells) {return results}

  const allCellsIndex = window.SCP.violinCellIndexes[gene]

  if (!cellFaceting) {return results}
  const filteredValues = {}

  const filteredCellIndexes = new Set()
  for (let i = 0; i < filteredCells.length; i++) {
    filteredCellIndexes.add(filteredCells[i].allCellsIndex)
  }

  Object.keys(results.values).forEach(group => {
    filteredValues[group] = {
      annotations: [],
      cells: [],
      name: group,
      y: []
    }
    const cellNames = results.values[group].cells
    for (let i = 0; i < cellNames.length; i++) {
      const cellIndex = allCellsIndex[group][i]
      if (filteredCellIndexes.has(cellIndex)) {
        const cellName = cellNames[i]
        filteredValues[group].cells.push(cellName)
        filteredValues[group].y.push(results.values[group].y[i])
      }
    }
  })

  results.values = filteredValues

  return results
}

/**
 * Displays a violin plot of expression data for the given gene and study
 *
 * @param studyAccession {String} the study accession
 * @param genes {Array[String]} array of gene names
 * @param cluster {String} the name of the cluster, or blank/null for the study's default
 * @param annotation {Object} an object with name, type, and scope attributes
 * @param subsample {String} a string for the subsampel to be retrieved.
 * @param consensus {String} for multi-gene expression plots
 * @param distributionPlot {String} 'box' or 'violin' for the plot type (default is violin)
 * @param distributionPoints {String} 'none' 'all' 'suspectedoutliers' or 'outliers'
 * @param setAnnotationList {Function} for global gene search and other places where a single call is used to
 *   fetch both the default expression data and the cluster menu options, a function that will be
 *   called with the annotationList returned by that call.
*/
function RawStudyViolinPlot({
  studyAccession, genes, cluster, annotation, subsample, consensus, distributionPlot, distributionPoints,
  updateDistributionPlot, setAnnotationList, dimensions={}, cellFaceting, filteredCells
}) {
  const [isLoading, setIsLoading] = useState(false)
  // array of gene names as they are listed in the study itself
  const [studyGeneNames, setStudyGeneNames] = useState([])
  const [graphElementId] = useState(_uniqueId('study-violin-'))
  const [renderedCluster, setRenderedCluster] = useState('')
  const [renderedAnnotation, setRenderedAnnotation] = useState('')
  const { ErrorComponent, setShowError, setError } = useErrorMessage()

  /** renders received expression data from the server */
  async function renderData([results, perfTimes], cellFaceting) {
    let distributionPlotToUse = distributionPlot
    if (!distributionPlotToUse) {
      distributionPlotToUse = defaultDistributionPlot
    }

    const filteredResults = await filterResults(
      studyAccession, cluster, annotation, genes[0],
      results, cellFaceting, filteredCells
    )

    const startTime = performance.now()

    renderViolinPlot(
      graphElementId,
      results,
      {
        plotType: distributionPlotToUse,
        showPoints: distributionPoints,
        dimensions
      }
    )

    perfTimes.plot = performance.now() - startTime

    logViolinPlot(
      { genes, distributionPlotToUse, distributionPoints },
      perfTimes
    )
    setStudyGeneNames(results.gene_names)
    setRenderedCluster(results.rendered_cluster)
    setRenderedAnnotation(results.rendered_annotation.split('--')[0])
    if (setAnnotationList) {
      setAnnotationList(results.annotation_list)
    }
    setShowError(false)
    setIsLoading(false)
  }

  /** handles fetching the expression data (and menu option data) from the server */
  useEffect(() => {
    setIsLoading(true)
    fetchExpressionViolin(
      studyAccession,
      genes,
      cluster,
      annotation.name,
      annotation.type,
      annotation.scope,
      subsample,
      consensus
    )
      .then(([results, perfTimes]) => {
        renderData([results, perfTimes], cellFaceting, filteredCells)
      }).catch(error => {
        Plotly.purge(graphElementId)
        setError(error)
        setShowError(true)
        setIsLoading(false)
      })
  }, [ // do a load from the server if any of the paramenters passed to fetchExpressionViolin have changed
    studyAccession,
    genes[0],
    cluster,
    annotation.name,
    annotation.scope,
    subsample,
    consensus,
    filteredCells?.join(',')
  ])

  // useEffect for handling render param re-renders
  useUpdateEffect(() => {
    // Don't try to update the if the data hasn't loaded yet
    if (!isLoading && studyGeneNames.length > 0) {
      setIsLoading(true)
      setTimeout(() => {
        updateViolinPlot(graphElementId, distributionPlot, distributionPoints)
        setIsLoading(false)
      }, 0)
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

  return (
    <div className="plot">
      { ErrorComponent }
      {!isLoading &&
        <ViolinPlotTitle
          cluster={renderedCluster}
          annotation={renderedAnnotation}
          genes={studyGeneNames}
          consensus={consensus}
        />
      }
      <div
        className="expression-graph"
        id={graphElementId}
        data-testid={graphElementId}
      >
      </div>
      {
        isLoading && <LoadingSpinner testId={`${graphElementId}-loading-icon`}/>
      }
    </div>
  )
}

const StudyViolinPlot = withErrorBoundary(RawStudyViolinPlot)
export default StudyViolinPlot


/** Formats expression data for Plotly, draws violin (or box) plot */
function renderViolinPlot(target, results, { plotType, showPoints, dimensions }) {
  const traceData = getViolinTraces(results.values, showPoints, plotType)
  const layout = getViolinLayout(results.y_axis_title, dimensions)
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
  const data = Object.entries(resultValues)
    .sort((a, b) => a[0].localeCompare(b[0], 'en', { numeric: true, ignorePunctuation: true }))
    .map(([traceName, traceData], index) => {
      // Plotly violin trace creation, adding to main array
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
function getViolinLayout(expressionLabel, dimensions) {
  const { width, height } = dimensions
  return {
    width,
    height,
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
      t: 20,
      b: 140
    },
    autosize: true
  }
}
