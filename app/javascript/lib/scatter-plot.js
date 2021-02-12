/**
 * @fileoverview Basic functions for scatter plots
 *
 * This code is used for scatter plots in the Study Overview page.  Scatter
 * plots are shown in several ways in the Explore tab of Study Overview,
 * when viewing the tab by default, upon searching a single gene, and (soon)
 * upon searching multiple genes.
 *
 * See file overview atop `explore-default.js` for higher-level notes.
 */

import $ from 'jquery'
import Plotly from 'plotly.js-dist'

import { labelFont, getColorBrewerColor } from 'lib/plot'
import { fetchCluster } from 'lib/scp-api'

// List of raw plots (API data + UI props, but not yet Plotly-processed)
let scatterPlots = []

/** Empty list of raw scatter plots */
export function clearScatterPlots() {
  scatterPlots = []
}

/**
 * Resize Plotly scatter plots, e.g. on window resize or "View Options" click
 */
export function resizeScatterPlots() {
  scatterPlots.forEach(rawPlot => {
    const target = rawPlot.plotId
    const layout = getScatterPlotLayout(rawPlot)
    Plotly.relayout(target, layout)
  })
}

/** Change Plotly scatter plot color scales */
export function setScatterPlotColorScales(theme) {
  scatterPlots.forEach(rawPlot => {
    const target = rawPlot.plotId
    const dataUpdate = { 'marker.colorscale': theme }
    Plotly.update(target, dataUpdate)
  })
}

/** Get Plotly layout object for scatter plot */
export function getBaseLayout(height, width) {
  const font = labelFont

  const layout = {
    hovermode: 'closest',
    height,
    width,
    font
  }
  return layout
}

/** Gets Plotly layout scene props for 3D scatter plot */
export function get3DScatterProps(camera, cluster) {
  const { domainRanges, axes } = cluster
  const { titles, ranges, aspects } = axes

  const scene = {
    camera,
    aspectmode: 'cube',
    xaxis: { title: titles.x, autorange: true, showticklabels: false },
    yaxis: { title: titles.y, autorange: true, showticklabels: false },
    zaxis: { title: titles.z, autorange: true, showticklabels: false }
  }

  if (domainRanges) {
    scene.xaxis.autorange = false
    scene.xaxis.range = ranges.x
    scene.yaxis.autorange = false
    scene.yaxis.range = ranges.y
    scene.zaxis.autorange = false
    scene.zaxis.range = ranges.x
    scene.aspectmode = aspects.mode,
    scene.aspectratio = {
      x: aspects.x,
      y: aspects.y,
      z: aspects.z
    }
  }

  return scene
}

/** Gets Plotly layout props for 2D scatter plot */
export function get2DScatterProps(cluster) {
  const {
    axes, domainRanges, hasCoordinateLabels, coordinateLabels
  } = cluster
  const { titles } = axes

  const layout = {
    xaxis: { title: titles.x },
    yaxis: { title: titles.y }
  }

  if (cluster.isAnnotatedScatter === false) {
    layout.xaxis.showticklabels = false
    layout.yaxis.scaleanchor = 'x'
    layout.yaxis.showticklabels = false
    layout.margin = {
      t: 25,
      r: 0,
      b: 20,
      l: 0
    }
  }

  // if user has supplied a range, set that, otherwise let Plotly autorange
  if (domainRanges) {
    layout.xaxis.range = domainRanges.x
    layout.yaxis.range = domainRanges.y
  } else {
    layout.xaxis.autorange = true
    layout.yaxis.autorange = true
  }

  if (hasCoordinateLabels) {
    layout.annotations = coordinateLabels
  }

  return layout
}

/** Set colors for group annotations */
export function setMarkerColors(data) {
  return data.map((trace, i) => {
    trace.marker.color = getColorBrewerColor(i)
    return trace
  })
}

/**
* Get height and width for a to-be-rendered cluster plot
*
* @param {Integer} numRows Number of rows of plots
* @param {Integer} numColumns Number of columns of plots
* @param {Number} verticalPad Space for e.g. page header, search, nav tabs
* @param {Number} horizontalPad Space to left and right of plots gallery
*/
function calculatePlotRect(
  numRows, numColumns, verticalPad=225, horizontalPad=80
) {
  // Get height
  const $ideo = $('#_ideogram')
  const ideogramHeight = $ideo.length ? $ideo.height() : 0

  // Height of screen viewport, minus fixed-height elements above gallery
  const galleryHeight = $(window).height() - verticalPad - ideogramHeight

  let height = galleryHeight
  if (numRows > 1) {
    // Fill as much gallery height as possible, but show tip of next row
    // as an affordance that the gallery is vertically scrollable.
    const secondRowTipHeight = 100
    height = height - secondRowTipHeight
  }

  // Get width, and account for expanding "View Options" after page load
  const baseWidth = $('#render-target .tab-content').actual('width')
  let width = (baseWidth - horizontalPad) / numColumns

  // Ensure plots aren't too small.
  // This was needed as of 2020-12-14 to avoid a Plotly error in single-gene
  // view: "Something went wrong with axes scaling"
  height = Math.max(height, 200)
  width = Math.max(width, 200)

  return { height, width }
}

/** Get layout object with various Plotly scatter plot display parameters */
function getScatterPlotLayout(rawPlot) {
  const { numRows, numColumns } = rawPlot
  const { height, width } = calculatePlotRect(numRows, numColumns)
  let layout = getBaseLayout(height, width)

  let dimensionProps
  if (rawPlot.is3D) {
    const camera = $('#cluster-plot').data('camera')
    dimensionProps = get3DScatterProps(camera, rawPlot)
    layout.scene = dimensionProps
  } else {
    dimensionProps = get2DScatterProps(rawPlot)
    layout = Object.assign(layout, dimensionProps)
  }

  // Set any layout props defined upstream
  if (rawPlot.layout) {
    Object.assign(layout, rawPlot.layout)
  }

  // Give space for legend below scatter plot
  if (rawPlot.description) {layout.height -= 20}

  return layout
}

/** Renders a Plotly scatter plot for "Clusters" tab */
function renderScatterPlot(rawPlot, plotId, legendId) {
  let { data } = rawPlot

  const layout = getScatterPlotLayout(rawPlot)

  if (rawPlot.annotParams.type === 'group' && !rawPlot.gene) {
    data = setMarkerColors(data)
  }
  performance.measure('json received to start plot', 'json_returned')
  performance.mark('plotly_started')
  Plotly.newPlot(plotId, data, layout)
  performance.measure('plot started to plot render', 'plotly_started')
  console.log(performance.getEntriesByType("measure"))
  if (legendId) {
    $(`#${legendId}`).html(
      `<p class="text-center help-block">${rawPlot.description}</p>`
    )
  }

  // access actual target div, not jQuery object wrapper for relayout event
  const scatterPlotDiv = document.getElementById(plotId)
  scatterPlotDiv.on('plotly_relayout', cameraData => {
    if (typeof cameraData['scene.camera'] !== 'undefined') {
      const newCamera = cameraData['scene.camera']
      $(`#${plotId}`).data('camera', newCamera)
    }
  })
}

/**
 * Load and draw scatter plot.  Handles clusters and spatial groups, numeric
 * and group annotations.
 *
 * @param {Object} apiParams Parameters for `/clusters` plot API endpoint
 * @param {Object} props Plot UI properties not from plot API data
 */
export async function scatterPlot(apiParams, props) {
  // Copy by value; preserves properties (e.g. plotId) across `await`
  props = Object.assign({}, props)

  const { plotId, hasLegend } = props

  const legendId = (hasLegend ? `${plotId}-legend` : null)
  const legendHtml = (hasLegend ? `<div id="${legendId}"></div>` : '')

  $(props.selector).append(
    `<div id="${plotId}" class="plot">${legendHtml}</div>`
  )

  // Set default number of rows and columns of plots
  if (!props.numRows) {props.numRows = 1}
  if (!props.numColumns) {props.numColumns = 1}

  const $plotElement = $(`#${plotId}`)
  const spinnerTarget = $plotElement[0]
  const spinner = new Spinner(window.opts).spin(spinnerTarget)
  // $plotElement.data('spinner', spinner)

  const { accession, cluster, annotation, subsample, gene } = apiParams
  let isAnnotatedScatter = null
  if (
    'isAnnotatedScatter' in apiParams && apiParams.isAnnotatedScatter
  ) {
    isAnnotatedScatter = true
  }

  $('#search_annotation').val(annotation)
  $('#gene_set_annotation').val(annotation)

  let fetchedData = await fetchCluster(
    accession, cluster, annotation, subsample, null, gene, isAnnotatedScatter
  )

  if ( fetchedData.media_url ) {
    const mediaUrl = fetchedData.media_url
    const mediaHeaders = {
      'Authorization': 'Bearer ' + window.SCP.userAccessToken
    }
    fetchedData = await fetch(mediaUrl, { headers: mediaHeaders }).then(response => response.json())
  }

  const rawPlot = Object.assign(fetchedData, props)

  // Consider putting into a dictionary instead of a list
  scatterPlots.push(rawPlot)

  // render annotation toggler picker if needed
  if (rawPlot.annotParams.type == 'numeric') {
    $('#toggle-plots').html('')
  } else {
    // Consider restoring this; it was missing on production before refactor
    // $('#toggle-plots').html(
    //   '<a href="#" class="btn btn-default btn-sm" id="toggle-traces" ' +
    //     'data-toggle="tooltip" data-placement="left" data-trigger="hover" ' +
    //     'title="Click to toggle all annotations, or toggle individual ' +
    //       'annotations by clicking the legend entry"' +
    //   '>Toggle Annotations <i class="fas fa-toggle-on"></i></a>'
    // )
    // $('#toggle-traces').tooltip({
    //   container: 'body', placement: 'left', trigger: 'hover'
    // })
  }

  renderScatterPlot(rawPlot, plotId, legendId)

  spinner.stop()
}
