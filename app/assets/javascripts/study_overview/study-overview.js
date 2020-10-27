/**
* @fileoverview Default view of Explore tab in Study Overview
*
* Shows "Clusters" and sometimes "Genomes", etc.
*/

const study = window.SCP.study

window.SCP.startPendingEvent('user-action:page:view:site-study',
  { speciesList: window.SCP.taxons },
  'plot:',
  true)

/**
 * Render cluster code
 *
 * TODO: Move this to render-cluster.js, or some such
 */

/** Get Plotly layout object for scatter plot */
function getBaseLayout(height, font) {
  const layout = {
    hovermode: 'closest',
    margin: {
      t: 25,
      r: 0,
      b: 20,
      l: 0
    },
    height,
    font
  }
  return layout
}

/** Gets Plotly layout scene props for 3D scatter plot */
function get3DScatterProps(camera, cluster) {
  const { clusterHasRange, axes } = cluster
  const { titles, ranges, aspects } = axes

  const scene = {
    camera,
    aspectmode: 'cube',
    xaxis: { title: titles.x, autorange: true, showticklabels: false },
    yaxis: { title: titles.y, autorange: true, showticklabels: false },
    zaxis: { title: titles.z, autorange: true, showticklabels: false }
  }

  if (clusterHasRange) {
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
function get2DScatterProps(cluster) {
  const {
    axes, clusterHasRange, domainRanges, hasCoordinateLabels, coordinateLabels
  } = cluster
  const { titles } = axes

  const layout = {
    xaxis: { title: titles.x, showticklabels: false },
    yaxis: { title: titles.y, showticklabels: false, scaleanchor: 'x' }
  }

  // if user has supplied a range, set that, otherwise let Plotly autorange
  if (clusterHasRange) {
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

/** Renders Plotly scatter plot for "Clusters" tab */
function drawScatterPlot(data, is3D, height, labelFont) {
  const layout =
    getScatterPlotLayout(is3D, height, labelFont)

  Plotly.newPlot('cluster-plot', data, layout)

  // listener to redraw expression scatter with new color profile
  $('#colorscale').off('change')
  $('#colorscale').change(function() {
    const theme = $(this).val()
    data[0].marker.colorscale = theme
    console.log(`setting colorscale to ${theme}`)

    $('#search_colorscale').val(theme)
    Plotly.update('cluster-plot', data, layout)
  })

  const description =
    `<p class="text-center help-block">${window.SCP.cluster.description}</p>`
  $('#cluster-figure-legend').html(description)

  // access actual target div, not jQuery object wrapper for relayout event
  const clusterPlotDiv = document.getElementById('cluster-plot')
  clusterPlotDiv.on('plotly_relayout', cameraData => {
    if (typeof cameraData['scene.camera'] !== 'undefined') {
      const oldScene = $('#expression-plots').data('scatter-camera')
      const newCamera = cameraData['scene.camera']
      console.log(`Updating camera information; was ${JSON.stringify(oldScene)}`)
      $('#cluster-plot').data('camera', newCamera)
      console.log(`Update complete, camera data now ${JSON.stringify($('#cluster-plot').data('camera'))}`)
    }
  })
}


/**
 * End render cluster code
 */

/** Draws the scatter plot for the default Explore tab view */
function renderScatter() {
  // detach listener as it will be re-attached in response;
  // this helps reduce spurious errors
  $(window).off('resizeEnd')

  const target = $('#cluster-plot')[0]
  const spinner = new Spinner(window.opts).spin(target)
  $('#cluster-plot').data('spinner', spinner)

  const urlParams = window.getRenderUrlParams()
  const url = `${study.renderClusterPath}?${urlParams}`

  $.ajax({
    url,
    method: 'GET',
    dataType: 'script'
  })
}

/** Get layout object with various Plotly scatter plot display parameters */
function getScatterPlotLayout(is3D, height, labelFont) {
  let layout = getBaseLayout(height, labelFont)

  let dimensionProps
  if (is3D) {
    const camera = $('#cluster-plot').data('camera')
    dimensionProps = get3DScatterProps(camera, window.SCP.cluster)
  } else {
    dimensionProps = get2DScatterProps(window.SCP.cluster)
  }

  layout = Object.assign(layout, dimensionProps)

  return layout
}

// For inferCNV ideogram
$('#ideogram_annotation').on('change', function() {
  const ideogramFiles = study.ideogramFiles
  const fileId = $(this).val() // eslint-disable-line
  if (fileId !== '') {
    const ideogramAnnot = ideogramFiles[fileId]
    window.ideogramInferCnvSettings = ideogramAnnot.ideogram_settings
    window.initializeIdeogram(ideogramAnnot.ideogram_settings.annotationsPath)
  } else {
    $('#tracks-to-display, #_ideogramOuterWrap').html('')
    $('#ideogramTitle').remove()
  }
})

if (study.canVisualizeClusters) {
  $('#cluster-plot').data('rendered', false)

  const baseCamera = {
    'up': { 'x': 0, 'y': 0, 'z': 1 },
    'center': { 'x': 0, 'y': 0, 'z': 0 },
    'eye': { 'x': 1.25, 'y': 1.25, 'z': 1.25 }
  }

  $(document).ready(() => {
    // if tab position was specified in url, show the current tab
    if (window.location.href.split('#')[1] !== '') {
      const tab = window.location.href.split('#')[1]
      $(`#study-tabs a[href="#${tab}"]`).tab('show')
    }
    $('#cluster-plot').data('camera', baseCamera)
    // set default subsample option of 10K (if subsampled) or all cells
    if (window.SCP.numPointsCluster > 10000 && window.SCP.clusterIsSampled) {
      $('#subsample').val(10000)
      $('#search_subsample').val(10000)
    }

    renderScatter()
  })

  // listener for cluster nav, specific to study page
  $('#annotation').change(function() {
    $('#cluster-plot').data('rendered', false)
    const an = $(this).val() // eslint-disable-line
    // keep track for search purposes
    $('#search_annotation').val(an)
    $('#gene_set_annotation').val(an)
    renderScatter()
  })

  $('#subsample').change(function() {
    $('#cluster-plot').data('rendered', false)
    const sample = $(this).val() // eslint-disable-line
    $('#search_subsample').val(sample)
    $('#gene_set_subsample').val(sample)
    renderScatter()
  })

  $('#cluster').change(function() {
    $('#cluster-plot').data('rendered', false)
    const newCluster = $(this).val() // eslint-disable-line
    // keep track for search purposes
    $('#search_cluster').val(newCluster)
    $('#gene_set_cluster').val(newCluster)
    // grab currently selected annotation
    const currSubsample = $('#subsample').val()

    const params = [
      'cluster=', encodeURIComponent(newCluster),
      '&subsample=', encodeURIComponent(currSubsample)
    ].join('')
    const url = `${window.SCP.getNewAnnotationsPath}?${params}`

    // get new annotation options and re-render
    $.ajax({
      url,
      method: 'GET',
      dataType: 'script',
      complete(jqXHR, textStatus) {
        window.renderWithNewCluster(textStatus, renderScatter)
      }
    })
  })

  if (window.SCP.hasIdeogramInferCnvFiles) {
    // user has no clusters, but does have ideogram annotations
    $(document).ready(() => {
      const ideogramSelect = $('#ideogram_annotation')
      const firstIdeogram = $('#ideogram_annotation option')[1].value

      // manually trigger change to cause ideogram to render
      ideogramSelect.val(firstIdeogram).trigger('change')
    })
  }
}
