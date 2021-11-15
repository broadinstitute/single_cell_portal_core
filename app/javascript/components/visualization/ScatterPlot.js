import React, { useState, useEffect } from 'react'
import _uniqueId from 'lodash/uniqueId'
import Plotly from 'plotly.js-dist'

import { fetchCluster } from 'lib/scp-api'
import { logScatterPlot } from 'lib/scp-api-metrics'
import { log } from 'lib/metrics-api'
import { labelFont, getColorBrewerColor } from 'lib/plot'
import { UNSPECIFIED_ANNOTATION_NAME } from 'lib/cluster-utils'
import { useUpdateEffect } from 'hooks/useUpdate'
import PlotTitle from './PlotTitle'
import useErrorMessage from 'lib/error-message'
import { computeCorrelations } from 'lib/stats'
import { withErrorBoundary } from 'lib/ErrorBoundary'
import { getFeatureFlagsWithDefaults } from 'providers/UserProvider'
import LoadingSpinner from 'lib/LoadingSpinner'

// sourced from https://github.com/plotly/plotly.js/blob/master/src/components/colorscale/scales.js
export const SCATTER_COLOR_OPTIONS = [
  'Greys', 'YlGnBu', 'Greens', 'YlOrRd', 'Bluered', 'RdBu', 'Reds', 'Blues', 'Picnic',
  'Rainbow', 'Portland', 'Jet', 'Hot', 'Blackbody', 'Earth', 'Electric', 'Viridis', 'Cividis'
]

export const defaultScatterColor = 'Reds'
window.Plotly = Plotly

/** Renders the appropriate scatter plot for the given study and params
  * @param studyAccession {string} e.g. 'SCP213'
  * @param cluster {string} the name of the cluster, or blank/null for the study's default
  * @param annotation {obj} an object with name, type, and scope attributes
  * @param subsample {string} a string for the subsample to be retrieved.
  * @param consensus {string} for multi-gene expression plots
  * @param dimensions {obj} object with height and width, to instruct plotly how large to render itself
  *   this is useful for rendering to hidden divs
  * @param isCellSelecting whether plotly's lasso selection tool is enabled
  * @plotPointsSelected {function} callback for when a user selects points on the plot, which corresponds
  *   to the plotly "points_selected" event
  */
function RawScatterPlot({
  studyAccession, cluster, annotation, subsample, consensus, genes, scatterColor, dimensions,
  isAnnotatedScatter=false, isCorrelatedScatter=false, isCellSelecting=false, plotPointsSelected, dataCache
}) {
  const [isLoading, setIsLoading] = useState(false)
  const [bulkCorrelation, setBulkCorrelation] = useState(null)
  const [labelCorrelations, setLabelCorrelations] = useState(null)
  const [scatterData, setScatterData] = useState(null)
  const [graphElementId] = useState(_uniqueId('study-scatter-'))
  const { ErrorComponent, setShowError, setErrorContent } = useErrorMessage()

  /** Process scatter plot data fetched from server */
  function handleResponse(clusterResponse) {
    const [scatter, perfTimes] = clusterResponse
    const layout = getPlotlyLayout(dimensions, scatter)

    const traceArgs = {
      axes: scatter.axes,
      data: scatter.data,
      annotName: scatter.annotParams.name,
      annotType: scatter.annotParams.type,
      genes: scatter.genes,
      isAnnotatedScatter: scatter.isAnnotatedScatter,
      isCorrelatedScatter: scatter.isCorrelatedScatter,
      scatterColor,
      dataScatterColor: scatter.scatterColor,
      pointAlpha: scatter.pointAlpha,
      pointSize: scatter.pointSize,
      showPointBorders: scatter.showClusterPointBorders,
      is3D: scatter.is3D,
      labelCorrelations
    }
    let plotlyTraces = getPlotlyTraces(traceArgs)

    const startTime = performance.now()
    Plotly.react(graphElementId, plotlyTraces, layout)

    perfTimes.plot = performance.now() - startTime

    logScatterPlot({
      scatter, genes, width: dimensions.width, height: dimensions.height
    }, perfTimes)

    if (isCorrelatedScatter) {
      const rhoStartTime = performance.now()

      // Compute correlations asynchronously, to not block other rendering
      computeCorrelations(scatter).then(correlations => {
        const rhoTime = Math.round(performance.now() - rhoStartTime)
        setBulkCorrelation(correlations.bulk)
        const flags = getFeatureFlagsWithDefaults()
        if (flags.correlation_refinements) {
          traceArgs.labelCorrelations = correlations.byLabel
          plotlyTraces = getPlotlyTraces(traceArgs)
          Plotly.react(graphElementId, plotlyTraces, layout)
        }
        log('plot:correlations', { perfTime: rhoTime })
      })
    }

    setScatterData(scatter)
    setShowError(false)
    setIsLoading(false)
  }

  // Fetches plot data then draws it, upon load or change of any data parameter
  useEffect(() => {
    setIsLoading(true)
    // use a data cache if one has been provided, otherwise query scp-api directly
    const fetchMethod = dataCache ? dataCache.fetchCluster : fetchCluster
    fetchMethod({
      studyAccession,
      cluster,
      annotation: annotation ? annotation : '',
      subsample,
      consensus,
      genes,
      isAnnotatedScatter,
      isCorrelatedScatter
    }).then(handleResponse).catch(error => {
      Plotly.purge(graphElementId)
      setErrorContent(error.message)
      setShowError(true)
      setIsLoading(false)
    })
  }, [cluster, annotation.name, subsample, consensus, genes.join(','), isAnnotatedScatter])

  // Handles Plotly `data` updates, e.g. changes in color profile
  useUpdateEffect(() => {
    // Don't try to update the color if the graph hasn't loaded yet
    if (scatterData && !isLoading) {
      const dataUpdate = { 'marker.colorscale': scatterColor }
      Plotly.update(graphElementId, dataUpdate)
    }
  }, [scatterColor])

  // Handles cell select mode updates
  useUpdateEffect(() => {
    // Don't try to update the color if the graph hasn't loaded yet
    if (scatterData && !isLoading) {
      const newDragMode = getDragMode(isCellSelecting)
      Plotly.relayout(graphElementId, { dragmode: newDragMode })
      if (!isCellSelecting) {
        Plotly.restyle(graphElementId, { selectedpoints: [null] })
      }
    }
  }, [isCellSelecting])

  // Adjusts width and height of plots upon toggle of "View Options"
  useUpdateEffect(() => {
    // Don't update if the graph hasn't loaded yet
    if (scatterData && !isLoading) {
      const { width, height } = dimensions
      const layoutUpdate = { width, height }
      Plotly.relayout(graphElementId, layoutUpdate)
    }
  }, [dimensions.width, dimensions.height])


  useEffect(() => {
    $(`#${graphElementId}`).on('plotly_selected', plotPointsSelected)
    $(`#${graphElementId}`).on('plotly_legendclick', logLegendClick)
    $(`#${graphElementId}`).on('plotly_legenddoubleclick', logLegendDoubleClick)
    return () => {
      $(`#${graphElementId}`).off('plotly_selected')
      $(`#${graphElementId}`).off('plotly_legendclick')
      $(`#${graphElementId}`).off('plotly_legenddoubleclick')
      Plotly.purge(graphElementId)
    }
  }, [])

  return (
    <div className="plot">
      { ErrorComponent }
      { scatterData &&
        <PlotTitle
          cluster={scatterData.cluster}
          annotation={scatterData.annotParams.name}
          subsample={scatterData.subsample}
          genes={scatterData.genes}
          consensus={scatterData.consensus}
          isCorrelatedScatter={isCorrelatedScatter}
          correlation={bulkCorrelation}/>
      }
      <div
        className="scatter-graph"
        id={graphElementId}
        data-testid={graphElementId}
      >
      </div>
      <p className="help-block">
        { scatterData && scatterData.description &&
          <span>{scatterData.description}</span>
        }
      </p>

      {
        isLoading &&
        <LoadingSpinner data-testid={`${graphElementId}-loading-icon`}/>
      }
    </div>
  )
}

const ScatterPlot = withErrorBoundary(RawScatterPlot)
export default ScatterPlot

/** Get entries for scatter plot legend, shown at right of graphic */
function getLegendEntries(data, pointSize, labelCorrelations) {
  const traceCounts = countOccurences(data.annotations)
  const legendEntries = Object.keys(traceCounts)
    .sort(traceNameSort) // sort keys so we assign colors in the right order
    .map((label, index) => {
      let entry = `${label} (${traceCounts[label]} points)`
      if (labelCorrelations) {
        const correlation = Math.round(labelCorrelations[label] * 100) / 100

        // ρ = rho = Spearman's rank correlation coefficient
        entry = `${label} (${traceCounts[label]} points, ρ = ${correlation})`
      }

      return {
        target: label,
        value: {
          name: entry,
          legendrank: index,
          marker: {
            color: getColorBrewerColor(index),
            size: pointSize
          }
        }
      }
    })

  return legendEntries
}

/** get the array of plotly traces for plotting */
export function getPlotlyTraces({
  axes,
  data,
  annotType,
  annotName,
  genes,
  isAnnotatedScatter,
  isCorrelatedScatter,
  scatterColor,
  dataScatterColor,
  pointAlpha,
  pointSize,
  showPointBorders,
  is3D,
  labelCorrelations
}) {
  const trace = {
    type: is3D ? 'scatter3d' : 'scattergl',
    mode: 'markers',
    opacity: pointAlpha ? pointAlpha : 1
  }

  const appliedScatterColor = getScatterColorToApply(dataScatterColor, scatterColor)
  const isGeneExpressionForColor = genes.length && !isCorrelatedScatter && !isAnnotatedScatter

  if (annotType === 'group' && !isGeneExpressionForColor) {
    // default cluster scatter plot
    // this currently shares some code with the 'else' block below, but the code
    // below will need to be refactored when we cease using plotly transforms.
    trace.x = data.x
    trace.y = data.y
    if (is3D) {
      trace.z = data.z
    }
    trace.annotations = data.annotations,
    trace.cells = data.cells
    // use plotly's groupby transformation to make the traces
    const legendEntries = getLegendEntries(data, pointSize, labelCorrelations)
    trace.transforms = [{
      type: 'groupby',
      groups: data.annotations,
      styles: legendEntries
    }]
  } else {
    // for non-clustered plots, we pass in a single trace with all the points
    let colors
    if (isGeneExpressionForColor) {
      // sort the points by order of expression
      const expressionsWithIndices = new Array(data.expression.length)
      for (let i = 0; i < data.expression.length; i++) {
        expressionsWithIndices[i] = [data.expression[i], i]
      }
      expressionsWithIndices.sort((a, b) => a[0] - b[0])
      // initialize the other arrays (see )
      trace.x = new Array(data.expression.length)
      trace.y = new Array(data.expression.length)
      if (is3D) {
        trace.z = new Array(data.expression.length)
      }
      trace.annotations = new Array(data.expression.length)
      trace.cells = new Array(data.expression.length)
      colors = new Array(data.expression.length)
      for (let i = 0; i < expressionsWithIndices.length; i++) {
        // now that we know the indices, reorder the other data arrays
        const sortedIndex = expressionsWithIndices[i][1]
        trace.x[i] = data.x[sortedIndex]
        trace.y[i] = data.y[sortedIndex]
        if (is3D) {
          trace.z[i] = data.z[sortedIndex]
        }
        trace.cells[i] = data.cells[sortedIndex]
        trace.annotations[i] = data.annotations[sortedIndex]
        colors[i] = expressionsWithIndices[i][0]
      }
    } else {
      trace.x = data.x
      trace.y = data.y
      if (is3D) {
        trace.z = data.z
      }
      trace.annotations = data.annotations,
      trace.cells = data.cells
      colors = isGeneExpressionForColor ? data.expression : data.annotations
    }

    trace.marker = {
      line: { color: 'rgb(40,40,40)', width: 0 },
      size: pointSize
    }
    const title = isGeneExpressionForColor ? axes.titles.magnitude : annotName
    if (!isAnnotatedScatter) {
      Object.assign(trace.marker, {
        showscale: true,
        colorscale: appliedScatterColor,
        color: colors,
        colorbar: { title, titleside: 'right' }
      })
      // if expression values are all zero, set max/min manually so the zeros still look like zero
      // see SCP-2957
      if (genes.length && !colors.some(val => val !== 0)) {
        trace.marker.cmin = 0
        trace.marker.cmax = 1
      }
    }
  }
  addHoverLabel(trace, annotName, annotType, genes, isAnnotatedScatter, isCorrelatedScatter, axes)
  return [trace]
}

/**
 * Return a hash of value=>count for the passed-in array
 * This is surprisingly quick even for large arrays, but we'd rather we
 * didn't have to do this.  See https://github.com/plotly/plotly.js/issues/5612
*/
function countOccurences(array) {
  return array.reduce((acc, curr) => {
    if (!acc[curr]) {
      acc[curr] = 1
    } else {
      acc[curr] += 1
    }
    return acc
  }, {})
}

/** sort trace names lexically, but always putting 'unspecified' last */
function traceNameSort(a, b) {
  if (a === UNSPECIFIED_ANNOTATION_NAME) {return 1}
  if (b === UNSPECIFIED_ANNOTATION_NAME) {return -1}
  return a.localeCompare(b, 'en', { numeric: true, ignorePunctuation: true })
}

/** makes the data trace attributes (cells, trace name) available via hover text */
function addHoverLabel(trace, annotName, annotType, genes, isAnnotatedScatter, isCorrelatedScatter, axes) {
  trace.text = trace.cells
  // use the 'meta' property so annotations are exposed to the hover template
  // see https://community.plotly.com/t/hovertemplate-does-not-show-name-property/36139
  trace.meta = trace.annotations
  let groupHoverTemplate = '(%{x}, %{y})<br><b>%{text}</b><br>%{meta}<extra></extra>'
  if (isAnnotatedScatter) {
    // for annotated scatter, just show coordinates and cell name
    groupHoverTemplate = `(%{x}, %{y})<br>%{text}`
  } else if ((annotType === 'numeric' || genes.length) && !isCorrelatedScatter) {
    // this is a graph with a continuous color scale
    // the bottom row of the hover will either be the expression value, or the annotation value
    const bottomRowLabel = genes.length ? axes.titles.magnitude : annotName
    groupHoverTemplate = `(%{x}, %{y})<br>%{text} (%{meta})<br>${bottomRowLabel}: %{marker.color}<extra></extra>`
  }
  trace.hovertemplate = groupHoverTemplate
}

/** sets the scatter color on the given races.  If no color is specified, it reads the color from the data */
function getScatterColorToApply(dataScatterColor, scatterColor) {
  // Set color scale
  if (!scatterColor) {
    scatterColor = dataScatterColor
  }
  if (!scatterColor) {
    scatterColor = defaultScatterColor
  }
  return scatterColor
}

/** Gets Plotly layout object for scatter plot */
function getPlotlyLayout({ width, height }={}, {
  axes,
  userSpecifiedRanges,
  hasCoordinateLabels,
  coordinateLabels,
  isAnnotatedScatter,
  isCorrelatedScatter,
  is3D,
  isCellSelecting=false,
  genes,
  annotParams
}) {
  const layout = {
    hovermode: 'closest',
    font: labelFont,
    dragmode: getDragMode(isCellSelecting)
  }
  if (is3D) {
    layout.scene = get3DScatterProps({
      userSpecifiedRanges, axes, hasCoordinateLabels,
      coordinateLabels
    })
  } else {
    const props2d = get2DScatterProps({
      axes,
      userSpecifiedRanges,
      hasCoordinateLabels,
      coordinateLabels,
      isAnnotatedScatter,
      isCorrelatedScatter
    })
    Object.assign(layout, props2d)
  }
  if (annotParams && annotParams.name) {
    layout.legend = {
      itemsizing: 'constant',
      title: { text: annotParams.name },
      y: 0.94
    }
  }
  layout.width = width
  layout.height = height
  return layout
}

/** Gets Plotly layout object for two-dimensional scatter plot */
function get2DScatterProps({
  axes,
  userSpecifiedRanges,
  hasCoordinateLabels,
  coordinateLabels,
  isAnnotatedScatter,
  isCorrelatedScatter
}) {
  const { titles } = axes

  const layout = {
    xaxis: { title: titles.x, range: axes?.ranges?.x },
    yaxis: { title: titles.y, range: axes?.ranges?.y }
  }

  if (isAnnotatedScatter === false && isCorrelatedScatter === false) {
    layout.xaxis.showticklabels = false
    layout.yaxis.scaleanchor = 'x'
    layout.yaxis.showticklabels = false
    layout.margin = {
      t: 10,
      r: 0,
      b: 20,
      l: 0
    }
  } else {
    layout.margin = {
      t: 10,
      r: 0,
      b: 50,
      l: 50
    }
  }

  // if user has supplied a range, set that, otherwise let Plotly autorange
  if (userSpecifiedRanges) {
    layout.xaxis.range = userSpecifiedRanges.x
    layout.yaxis.range = userSpecifiedRanges.y
  } else {
    layout.xaxis.autorange = true
    layout.yaxis.autorange = true
  }

  if (hasCoordinateLabels && !isAnnotatedScatter && !isCorrelatedScatter) {
    // don't show coordinate labels on annotated scatters, since the axes are different
    layout.annotations = coordinateLabels
  }

  return layout
}

const baseCamera = {
  up: { x: 0, y: 0, z: 1 },
  center: { x: 0, y: 0, z: 0 },
  eye: { x: 1.25, y: 1.25, z: 1.25 }
}

/** Gets Plotly layout scene props for 3D scatter plot */
export function get3DScatterProps({
  userSpecifiedRanges, axes, hasCoordinateLabels,
  coordinateLabels
}) {
  const { titles, aspects } = axes

  const scene = {
    baseCamera,
    aspectmode: 'cube',
    xaxis: { title: titles.x, autorange: true, showticklabels: false },
    yaxis: { title: titles.y, autorange: true, showticklabels: false },
    zaxis: { title: titles.z, autorange: true, showticklabels: false }
  }

  if (userSpecifiedRanges) {
    scene.xaxis.autorange = false
    scene.xaxis.range = userSpecifiedRanges.x
    scene.yaxis.autorange = false
    scene.yaxis.range = userSpecifiedRanges.y
    scene.zaxis.autorange = false
    scene.zaxis.range = userSpecifiedRanges.z
    scene.aspectmode = aspects.mode,
    scene.aspectratio = {
      x: aspects.x,
      y: aspects.y,
      z: aspects.z
    }
  }

  if (hasCoordinateLabels) {
    scene.annotations = coordinateLabels
  }

  return scene
}

/** get the appropriate plotly dragmode option string */
function getDragMode(isCellSelecting) {
  return isCellSelecting ? 'lasso' : 'lasso, select'
}


let currentClickCall = null

/** we don't want to fire two single click events for a double click, so
 * we wait until we've confirmed a click isn't a double click before logging it.
 * Unfortunately (despite the docs indicating otherwise), there doesn't seem to be
 * a way of getting the text of the clicked annotation
 */
function logLegendClick(event) {
  clearTimeout(currentClickCall)
  currentClickCall = setTimeout(() => log('click:scatterlegend:single'), 300)
}

/** log a double-click on a plotly graph legend */
function logLegendDoubleClick(event) {
  clearTimeout(currentClickCall)
  log('click:scatterlegend:double')
}
