import PlotUtils from '~/lib/plot'
const { morpheusTabManager, logMorpheusPerfTime } = PlotUtils
import { morpheusErrorHandler } from '~/lib/error-message'

/** Render Morpheus heatmap */
export function renderHeatmap({
  target, expressionValuesURL, annotationCellValuesURL, annotationName,
  fit, rowCentering, sortColumns=true, setShowError, setError, genes, colorMin, colorMax
}) {
  const $target = $(target)
  $target.empty()

  const config = {
    dataset: expressionValuesURL,
    el: $target,
    menu: null,
    error: morpheusErrorHandler($target, setShowError, setError),
    colorScheme: {
      scalingMode: rowCentering !== '' ? 'fixed' : 'relative',
      stepped: false
    },
    focus: null,
    // We implement our own trivial tab manager as it seems to be the only way
    // (after 2+ hours of digging) to prevent morpheus auto-scrolling
    // to the heatmap once it's rendered
    tabManager: morpheusTabManager($target),
    loadedCallback: () => logMorpheusPerfTime(target, 'heatmap', genes)
  }
  if (colorMin || colorMax) {
    config.colorScheme.values = [colorMin, colorMax]
  }

  // Fit rows, columns, or both to screen
  if (fit === 'cols') {
    config.columnSize = 'fit'
  } else if (fit === 'rows') {
    config.rowSize = 'fit'
  } else if (fit === 'both') {
    config.columnSize = 'fit'
    config.rowSize = 'fit'
  } else if (fit === 'none') {
    config.columnSize = null
    config.rowSize = null
  } else {
    config.columnSize = null
    config.rowSize = null
  }

  // Load annotations if specified
  if (annotationCellValuesURL !== '') {
    config.columnAnnotations = [{
      file: annotationCellValuesURL,
      datasetField: 'id',
      fileField: 'NAME',
      include: [annotationName]
    }]
    if (sortColumns) {
      config.columnSortBy = [
        { field: annotationName, order: 0 }
      ]
    }
    config.columns = [
      { field: 'id', display: 'text' },
      { field: annotationName, display: 'color' }
    ]
    config.rows = [
      { field: 'id', display: 'text' }
    ]
  }
  return new window.morpheus.HeatMap(config)
}

/** updates the heatmap in response to a change in the fit parameter
 * @param morpheusHeatmap { HeatMap } a heatmap, such as returned from `renderHeatmap` above
 * @param fit { String } rows|cols|both|''  empty string resets to none
*/
export function refitHeatmap(morpheusHeatmap, fit='') {
  if (morpheusHeatmap && morpheusHeatmap.fitToWindow) {
    morpheusHeatmap.resetZoom()
    if (fit !== '') {
      morpheusHeatmap.fitToWindow({
        fitRows: fit === 'rows' || fit === 'both',
        fitColumns: fit === 'cols' || fit === 'both',
        repaint: true
      })
    }
  }
}
