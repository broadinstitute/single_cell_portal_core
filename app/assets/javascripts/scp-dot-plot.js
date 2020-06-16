/**
 * @fileoverview Functions for rendering dot plots using Morpheus.js
 *
 * Dot plots are similar to heatmaps, and better for summarizing expression
 * across many cells. The color of the dot is the median expression of a
 * cluster in a gene. The size of the dot is what percent of cells in the
 * cluster have expression (expr > 0) in the gene.
 *
 * Morpheus examples:
 * https://software.broadinstitute.org/morpheus/
 *
 * Morpheus source code:
 * https://github.com/cmap/morpheus.js
 */

const dotPlotColorScheme = {
  // Blue, purple, red.  These red and blue hues are accessible, per WCAG.
  colors: ['#0000BB', '#CC0088', '#FF0000'],

  // TODO: Incorporate expression units, once such metadata is available.
  values: [0, 0.5, 1]
}

/**
 * Returns SVG comprising the dot plot legend.
 */
function getLegendSvg(rects) {
  // Sarah N. asked for a note about non-zero in the legend, but it's unclear
  // if Morpheus supports non-zero.  It might, per the Collapse properties
  //
  //    pass_expression: '>',
  //    pass_value: '0',
  //
  // used below, but Morpheus still shows dots with "0.00".  This seems like a
  // contradiction.  So keep the note code, but don't show the note in the
  // legend until we can clarify.
  //
  // var nonzeroNote = '<text x="9" y="66">(non-zero)</text>';
  const nonzeroNote = ''

  // TODO:
  // Develop more robust coordinate offsets for colors and related text.
  // The very particular values for cx, x, etc. are manually polished and work
  // for these particular contents, but won't work once we enable users to
  // change the default size max. and min. values.  Defer work until SCP-1738.
  return (
    `<svg>
      <g id="dp-legend-size">
        <circle cx="20" cy="8" r="1"/>
        <circle cx="57.5" cy="8" r="3"/>
        <circle cx="90" cy="8" r="7"/>

        <text x="17" y="30">0</text>
        <text x="50" y="30">38</text>
        <text x="83" y="30">75</text>

        <text x="15" y="52">% expressing</text>
      </g>
      <g id="dp-legend-color" transform="translate(200, 0)">
        ${rects}
        <text x="5" y="50">Expression</text>
        ${nonzeroNote}
      </g>
    <svg>`
  )
}

/**
 * Shows a legend for size and color below the dot plot.
 * the two target arguments are optional CSS selectors for where to render
 * If specified, 'legendTarget' must be an id selector, e.g. "#foobar"
 */
function renderDotPlotLegend(dotPlotTarget, legendTarget) {
  if (!legendTarget) {
    legendTarget = '#dot-plot-legend'
  }
  if (!dotPlotTarget) {
    dotPlotTarget = '#dot-plot'
  }

  $(legendTarget).remove()
  const scheme = dotPlotColorScheme
  const rects = scheme.colors.map((color, i) => {
    const value = scheme.values[i] // Expression threshold value

    // TODO:
    // A more robust, yet more complicated way to get textOffset this would
    // be to use getClientRect() or getBBox() after rendering to DOM to
    // determine each SVG text element's width, then adjusting the x attribute
    // accordingly to align at the middle of the corresponding rect for the
    // color stop.
    //
    // But that robust approach only adds value over this simple approach
    // when we need to support dynamic values.  Defer this TODO until SCP-1738.
    const textOffset = 4 - (String(value).length - 1) * 3

    return (
      `<g transform="translate(${i * 30}, 0)">
        <rect fill="${color}" width="15" height="15"/>
        <text x="${textOffset}" y="30">${value}</text>
      </g>`
    )
  }).join()

  const legend = getLegendSvg(rects)

  $(dotPlotTarget).append(`
    <div
      id="${legendTarget.substring(1)}"
      style="position: relative; top: 30px; left: 70px;">
    </div>
  `)
  document.querySelector(legendTarget).innerHTML = legend
}

/** Render Morpheus dot plot */
function renderMorpheusDotPlot(
  dataPath, annotPath, selectedAnnot, selectedAnnotType,
  target, annotations, fitType, dotHeight, legendTarget
) {
  console.log(`
    render status of ${target} at start: ${$(target).data('rendered')}
  `)
  $(target).empty()

  // Collapse by median
  const tools = [{
    name: 'Collapse',
    params: {
      shape: 'circle',
      collapse: ['Columns'],
      collapse_to_fields: [selectedAnnot],
      pass_expression: '>',
      pass_value: '0',
      percentile: '100',
      compute_percent: true
    }
  }]

  const config = {
    shape: 'circle',
    dataset: dataPath,
    el: $(target),
    menu: null,
    colorScheme: {
      scalingMode: 'relative'
    },
    tools
  }

  // Set height if specified, otherwise use default setting of 500 px
  if (dotHeight !== undefined) {
    config.height = dotHeight
  } else {
    config.height = 500
  }

  // Fit rows, columns, or both to screen
  if (fitType === 'cols') {
    config.columnSize = 'fit'
  } else if (fitType === 'rows') {
    config.rowSize = 'fit'
  } else if (fitType === 'both') {
    config.columnSize = 'fit'
    config.rowSize = 'fit'
  } else {
    config.columnSize = null
    config.rowSize = null
  }

  // Load annotations if specified
  if (annotPath !== '') {
    config.columnAnnotations = [{
      file: annotPath,
      datasetField: 'id',
      fileField: 'NAME',
      include: [selectedAnnot]
    }]
    config.columnSortBy = [
      { field: selectedAnnot, order: 0 }
    ]
    config.columns = [
      { field: selectedAnnot, display: 'text' }
    ]
    config.rows = [
      { field: 'id', display: 'text' }
    ]

    // Create mapping of selected annotations to colorBrewer colors
    const annotColorModel = {}
    annotColorModel[selectedAnnot] = {}
    const sortedAnnots = annotations['values'].sort()

    // Calling % 27 will always return to the beginning of colorBrewerSet
    // once we use all 27 values
    $(sortedAnnots).each((index, annot) => {
      annotColorModel[selectedAnnot][annot] = colorBrewerSet[index % 27]
    })
    config.columnColorModel = annotColorModel
  }

  config.colorScheme = dotPlotColorScheme

  // Log dot plot initialization in Google Analytics
  if (typeof window.dotPlot === 'undefined') {
    // Consistent with e.g. IGV, Ideogram
    ga('send', 'event', 'dot-plot', 'initialize')
    log('dot-plot:initialize')
  }

  // Instantiate dot plot and embed in DOM element
  window.dotPlot = new morpheus.HeatMap(config)
  window.dotPlot.tabManager.setOptions({ autohideTabBar: true })
  $(target).off()
  $(target).on('heatMapLoaded', (e, heatMap) => {
    // Remove verbose tab atop Morpheus dot plot
    const tabItems = dotPlot.tabManager.getTabItems()
    window.dotPlot.tabManager.setActiveTab(tabItems[1].id)
    window.dotPlot.tabManager.remove(tabItems[0].id)

    renderDotPlotLegend(target, legendTarget)

    // Remove "Options" toolbar button until legend can be updated upon
    // changing default options for size and color (SCP-1738).
    // setTimeout is a kludge, but seemingly the only way to do this.
    setTimeout(() => {
      const options = $('#dot-plots [data-action="Options"]')
      options.next('.morpheus-button-divider').remove()
      options.remove()
    }, 50)
  })

  // Set render variable to true for tests
  $(target).data('morpheus', dotPlot)
  $(target).data('rendered', true)
  console.log(`
    render status of ${target} at end: ${$(target).data('rendered')}
  `)
}

/** High-level function called from _expression_plots_view.html.erb */
function drawDotplot(height) { // eslint-disable-line no-unused-vars
  $(window).off('resizeEnd')

  // Clear out previous stored dotplot object
  $('#dot-plot').data('dotplot', null)

  // If height isn't specified, pull from stored value, defaults to 500
  if (height === undefined) {
    height = $('#dot-plot').data('height')
  }

  // Pull fit type as well, defaults to ''
  const fit = $('#dot-plot').data('fit')

  const selectedAnnot = $('#annotation').val()
  const annotName = selectedAnnot.split('--')[0]
  const annotType = selectedAnnot.split('--')[1]

  const cluster = $('#cluster').val()
  $('#search_cluster').val(cluster)
  $('#search_annotation').val('') // clear value first
  $('#search_annotation').val(selectedAnnot)

  const newAnnotPath = `
    ${dotPlotAnnotPathBase}
    ?cluster=${cluster}&
    annotation=${selectedAnnot}&
    request_user_token=${requestToken}`

  const renderUrlParams = getRenderUrlParams()
  // Get annotation values to set color values in Morpheus and
  // draw dotplot in callback
  $.ajax({
    url: `${dotPlotAnnotValuesPath}?${renderUrlParams}`,
    dataType: 'JSON',
    success(annotations) {
      renderMorpheusDotPlot(
        dataPath, newAnnotPath, annotName, annotType, '#dot-plot',
        annotations, fit, height
      )
    }
  })
}
