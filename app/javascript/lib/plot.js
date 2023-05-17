import { UNSPECIFIED_ANNOTATION_NAME } from '~/lib/cluster-utils'
import { log, logError } from '~/lib/metrics-api'

// Default plot colors, combining ColorBrewer sets 1-3 with tweaks to yellows.
const colorBrewerList = [
  '#e41a1c', '#377eb8', '#4daf4a', '#984ea3', '#ff7f00', '#a65628',
  '#f781bf', '#999999', '#66c2a5', '#fc8d62', '#8da0cb', '#e78ac3',
  '#a6d854', '#ffd92f', '#e5c494', '#b3b3b3', '#8dd3c7', '#bebada',
  '#fb8072', '#80b1d3', '#fdb462', '#b3de69', '#fccde5', '#d9d9d9',
  '#bc80bd', '#ccebc5', '#ffed6f'
]

const PlotUtils = function() {
  return 'placeholder component'
}


/**
 * Used in both categorical scatter plots and violin plots, to ensure
 * they use consistent friendly colors for annotations, etc.
 */
PlotUtils.getColorBrewerColor = function(index) {
  return colorBrewerList[index % 27]
}

// default title font settings for axis titles in plotly
PlotUtils.titleFont = {
  family: 'Helvetica Neue',
  size: 16,
  color: '#333'
}

// default label font settings for colorbar titles in plotly
PlotUtils.labelFont = {
  family: 'Helvetica Neue',
  size: 12,
  color: '#333'
}

PlotUtils.lineColor = 'rgb(40, 40, 40)'

/** returns an empty trace with arrays initialized based on expectedLength */
function emptyTrace(expectedLength, hasZvalues, hasExpression) {
  const trace = {
    x: new Array(expectedLength),
    y: new Array(expectedLength),
    annotations: new Array(expectedLength),
    cells: new Array(expectedLength),
    newLength: 0 // used to track the post-filter length -- NOT a plotly property
  }
  if (hasZvalues) {
    trace.z = new Array(expectedLength)
  }
  if (hasExpression) {
    trace.expression = new Array(expectedLength)
  }
  return trace
}

/** takes a plotly trace argument and filters out cells based on params.  will return the original object,
 * but with data arrays filtered as appropriate
 * @param hiddenTraces {String[]} array of label names to filter out
 * @param activeTraceLabel if specified, the traces will be sorted such that the activeTrace is plotted on top
 * @param groupByAnnotation {Boolean} whether to assemble separate traces for each label
 *
 * For performance, see https://docs.google.com/document/d/1JKmXp9gEY2Y_cshypBwLrpgBEKYcpBmMna0nf_7eeNw
 */
PlotUtils.filterTrace = function({
  trace, hiddenTraces=[], groupByAnnotation=false,
  activeTraceLabel, expressionFilter, expressionData, isSplitLabelArrays
}) {
  const isHidingByLabel = hiddenTraces && hiddenTraces.length
  const isFilteringByExpression = expressionFilter && expressionData &&
    (expressionFilter[0] !== 0 || expressionFilter[1] !== 1)
  const hasZvalues = !!trace.z
  const hasExpression = !!trace.expression
  if (isSplitLabelArrays) {
    trace = PlotUtils.splitTraceByAnnotationArray(trace, hasZvalues)
  }
  const oldLength = trace.x.length
  // if grouping by annotation, traceMap is a hash of annotation names to traces
  // otherwise, traceMap will just have a single 'all' trace
  const traceMap = {}
  const estTraceLength = groupByAnnotation ? Math.round(trace.x.length / 10) : trace.x.length
  let unfilteredCountsByLabel = { main: trace.x.length } // maintain a list of all cell counts by label for the legend
  const countsByLabel = {}
  if (groupByAnnotation) {
    unfilteredCountsByLabel = countValues(trace.annotations)
  }
  Object.keys(unfilteredCountsByLabel).forEach(key => {
    traceMap[key] = emptyTrace(estTraceLength, hasZvalues, hasExpression)
    traceMap[key].name = key
  })

  if (!isHidingByLabel && !isFilteringByExpression && !groupByAnnotation) {
    return [[trace], unfilteredCountsByLabel]
  }

  let expFilterMin
  let expFilterMax
  let expMin = 99999999
  let expMax = -99999999
  if (isFilteringByExpression) {
    expMin = PlotUtils.arrayMin(expressionData)
    expMax = PlotUtils.arrayMax(expressionData)
    // convert the expressionFilter, which is on a 0-1 scale, to the expression scale
    const totalRange = expMax - expMin
    expFilterMin = expMin + totalRange * expressionFilter[0]
    expFilterMax = expMin + totalRange * expressionFilter[1]
  }

  // this is the main filter/group loop.  Loop over every cell and determine whether it needs to be filtered,
  // and if it needs to be grouped.
  for (let i = 0; i < oldLength; i++) {
    // if we're not filtering by expression, or the cell is in the range, show it
    if (!isFilteringByExpression || (expressionData[i] >= expFilterMin && expressionData[i] <= expFilterMax)) {
      const fTrace = groupByAnnotation ? traceMap[trace.annotations[i]] : traceMap.main
      const newIndex = fTrace.newLength
      fTrace.x[newIndex] = trace.x[i]
      fTrace.y[newIndex] = trace.y[i]
      if (hasZvalues) {
        fTrace.z[newIndex] = trace.z[i]
      }
      fTrace.cells[newIndex] = trace.cells[i]
      fTrace.annotations[newIndex] = trace.annotations[i]
      if (hasExpression) {
        fTrace.expression[newIndex] = trace.expression[i]
      }
      fTrace.newLength++
    }
  }
  // now fix the length of the new arrays in each trace to the number of values that were written,
  // and push the traces into an array
  const traces = Object.values(traceMap)
  traces.forEach(fTrace => {
    const subArrays = [fTrace.x, fTrace.y, fTrace.z, fTrace.annotations, fTrace.expression, fTrace.cells]
    subArrays.forEach(arr => {
      if (arr) {
        arr.length = fTrace.newLength
      }
    })
    countsByLabel[fTrace.name] = fTrace.x.length
    delete fTrace.newLength
  })
  PlotUtils.sortTraces(traces, activeTraceLabel)
  PlotUtils.updateTraceVisibility(traces, hiddenTraces)
  const expRange = isFilteringByExpression ? [expMin, expMax] : null
  return [traces, countsByLabel, expRange]
}

/** split array-based (|-delimited) annotations into separate points.  this function is essentially a no-op
 * for labels that do not have | delimtiters
 */
PlotUtils.splitTraceByAnnotationArray = function(trace, hasZvalues) {
  const hasExpression = !!trace.expression
  const newTrace = {
    x: [],
    y: [],
    annotations: [],
    cells: []
  }
  if (hasZvalues) {
    newTrace.z = []
  }
  if (hasExpression) {
    newTrace.expression = []
  }

  // the jitterFraction controls the amount of displacement of points as a fraction of the graph width
  // The value of 400 was picked because assuming that point size
  // is ~3px, and the graph is rendered ~800px tall/wide, a displacement of 800/400 = ~2px is enough to push
  // the points far enough apart to be seen individually, but still be associated with each other.
  // this may be made more sophisticated later.
  const jitterFraction = 400
  // jitter will place cells in a 3x3 grid whose center is the actual coordinate
  const xJitterMods = [0, -1, 1, 1, -1, -1, 0, 1, 0]
  const yJitterMods = [0, -1, -1, 1, 1, 0, -1, 0, 1]
  let xJitter = 0
  let yJitter = 0

  const xRange = [PlotUtils.arrayMin(trace.x), PlotUtils.arrayMax(trace.x)]
  const yRange = [PlotUtils.arrayMin(trace.y), PlotUtils.arrayMax(trace.y)]
  xJitter = (xRange[1] - xRange[0]) / jitterFraction
  yJitter = (yRange[1] - yRange[0]) / jitterFraction


  // iterate over each point, and if the annotation is pipe-delimited, split it out
  for (let i = 0; i < trace.x.length; i++) {
    const subAnnotations = trace.annotations[i].split('|')
    subAnnotations.forEach((annot, annotIndex) => {
      newTrace.x.push(trace.x[i] + xJitter * xJitterMods[annotIndex % 9])
      newTrace.y.push(trace.y[i] + yJitter * yJitterMods[annotIndex % 9])

      if (hasZvalues) {
        newTrace.z.push(trace.z[i])
      }
      if (hasExpression) {
        newTrace.expression.push(trace.expression[i])
      }
      newTrace.cells.push(trace.cells[i])
      newTrace.annotations.push(annot)
    })
  }
  return newTrace
}

PlotUtils.updateTraceVisibility = function(traces, hiddenTraces) {
  traces.forEach(trace => {
    trace.visible = hiddenTraces.includes(trace.name) ? 'legendonly' : true
  })
}

/** Sort traces by number of cells (largest first), but always put the activeTraceLabel last
   * and the unspecified annotations first
   * If the activeLabel *is* the unspecified cells, then put them last
  */
PlotUtils.sortTraces = function(traces, activeTraceLabel) {
  const unspecifiedIsActive = activeTraceLabel === UNSPECIFIED_ANNOTATION_NAME
  /** sort function for implementing the logic described above */
  function traceCountsSort(a, b) {
    if (activeTraceLabel === a.name || (UNSPECIFIED_ANNOTATION_NAME === b.name && !unspecifiedIsActive)) {return 1}
    if (activeTraceLabel === b.name || (UNSPECIFIED_ANNOTATION_NAME === a.name && !unspecifiedIsActive)) {return -1}
    return b.x.length - a.x.length
  }

  return traces.sort(traceCountsSort)
}

/** sort the passsed in trace by expression value */
PlotUtils.sortTraceByExpression = function(trace) {
  const hasZ = !!trace.z
  const traceLength = trace.x.length
  const sortedTrace = {
    type: trace.type,
    mode: trace.mode
  }
  // sort the points by order of expression
  const expressionsWithIndices = new Array(traceLength)
  for (let i = 0; i < traceLength; i++) {
    expressionsWithIndices[i] = [trace.expression[i], i]
  }
  expressionsWithIndices.sort((a, b) => a[0] - b[0])

  // initialize the other arrays with their size
  // (see https://codeabitwiser.com/2015/01/high-performance-javascript-arrays-pt1/ for performance rationale)
  sortedTrace.x = new Array(traceLength)
  sortedTrace.y = new Array(traceLength)
  if (hasZ) {
    sortedTrace.z = new Array(traceLength)
  }
  sortedTrace.annotations = new Array(traceLength)
  sortedTrace.cells = new Array(traceLength)
  sortedTrace.expression = new Array(traceLength)

  // now that we know the indices, reorder the other data arrays
  for (let i = 0; i < expressionsWithIndices.length; i++) {
    const sortedIndex = expressionsWithIndices[i][1]
    sortedTrace.x[i] = trace.x[sortedIndex]
    sortedTrace.y[i] = trace.y[sortedIndex]
    if (hasZ) {
      sortedTrace.z[i] = trace.z[sortedIndex]
    }
    sortedTrace.cells[i] = trace.cells[sortedIndex]
    sortedTrace.annotations[i] = trace.annotations[sortedIndex]
    sortedTrace.expression[i] = expressionsWithIndices[i][0]
  }
  return sortedTrace
}

/**
 * Get color for the label, which can be applied to e.g. the icon or the trace
 */
PlotUtils.getColorForLabel = function(label, customColors={}, editedCustomColors={}, i) {
  if (label === '--Unspecified--' && !editedCustomColors[label] && !customColors[label]) {
    return 'rgba(80, 80, 80, 0.4)'
  }
  return editedCustomColors[label] ?? customColors[label] ?? PlotUtils.getColorBrewerColor(i)
}

/** Returns an array of labels, sorted in the order in which they should be displayed in the legend */
PlotUtils.getLegendSortedLabels = function(countsByLabel) {
  /** Sort annotation labels lexicographically, but always put the unspecified annotations last */
  function labelSort(a, b) {
    if (UNSPECIFIED_ANNOTATION_NAME === a) {return 1}
    if (UNSPECIFIED_ANNOTATION_NAME === b) {return -1}
    return a.localeCompare(b, 'en', { numeric: true, ignorePunctuation: true })
  }
  return Object.keys(countsByLabel).sort(labelSort)
}


/**
 * Return a hash of value=>count for the passed-in array
 * This is surprisingly quick even for large arrays, but we'd rather we
 * didn't have to do this.  See https://github.com/plotly/plotly.js/issues/5612
*/
function countValues(array) {
  try {
    return array.reduce((acc, curr) => {
      acc[curr] ||= 0
      acc[curr] += 1
      return acc
    }, {})
  } catch (error) {
    // This will log to both Mixpanel and Sentry
    logError('Error counting values for trace array', error)
  }
}

/**
 * More memory- and time-efficient analog of Math.min
 * From https://stackoverflow.com/a/13440842/10564415.
*/
PlotUtils.arrayMin = function(arr) {
  let len = arr.length; let min = Infinity
  while (len--) {
    if (arr[len] < min) {
      min = arr[len]
    }
  }
  return min
}

/**
 * More memory- and time-efficient analog of Math.max
 * From https://stackoverflow.com/a/13440842/10564415.
*/
PlotUtils.arrayMax = function(arr) {
  let len = arr.length; let max = -Infinity
  while (len--) {
    if (arr[len] > max) {
      max = arr[len]
    }
  }
  return max
}

PlotUtils.ideogramHeight = 140
PlotUtils.scatterLabelLegendWidth = 260

/** Get width and height available for plot components, since they may be first rendered hidden */
PlotUtils.getPlotDimensions = function({
  isTwoColumn=false,
  isMultiRow=false,
  verticalPad=250,
  horizontalPad=80,
  hasLabelLegend=false,
  hasTitle=false,
  showRelatedGenesIdeogram=false,
  showViewOptionsControls=true,
  showDifferentialExpressionTable=false
}) {
  // Account for options panel and DE table
  let baseWidth = $(window).width()
  if (showViewOptionsControls) {
    const unitWidth = showDifferentialExpressionTable ? 9 : 10
    baseWidth = Math.round(baseWidth * unitWidth / 12)
  }
  if (hasLabelLegend) {
    const factor = isTwoColumn ? 2 : 1
    horizontalPad += PlotUtils.scatterLabelLegendWidth * factor
  }
  let width = (baseWidth - horizontalPad) / (isTwoColumn ? 2 : 1)

  // Get height
  // Height of screen viewport, minus fixed-height elements above gallery
  let galleryHeight = $(window).height() - verticalPad

  if (showRelatedGenesIdeogram) {
    galleryHeight -= PlotUtils.ideogramHeight
  }

  if (hasTitle) {
    galleryHeight -= 20
  }
  let height = galleryHeight
  if (isMultiRow) {
    // Fill as much gallery height as possible, but show tip of next row
    // as an affordance that the gallery is vertically scrollable.
    const secondRowTipHeight = 70
    height = height - secondRowTipHeight
  }
  // ensure aspect ratio isn't too distorted
  if (height > width * 1.3) {
    height = Math.round(width * 1.3)
  }

  // Ensure plots aren't too small.
  // This was needed as of 2020-12-14 to avoid a Plotly error in single-gene
  // view: "Something went wrong with axes scaling"
  height = Math.max(height, 200)
  width = Math.max(width, 200)

  return { width, height }
}

/** return a trivial tab manager that handles focus and sizing
 * We implement our own trivial tab manager as it seems to be the only way
 * (after 2+ hours of digging) to prevent morpheus auto-scrolling
 * to a heatmap once it's rendered
 */
PlotUtils.morpheusTabManager = function($target) {
  return {
    add: options => {
      $target.empty()
      $target.append(options.$el)
      return { id: $target.attr('id'), $panel: $target }
    },
    setTabTitle: () => {},
    setActiveTab: () => {},
    getActiveTabId: () => {},
    getWidth: () => $target.actual('width'),
    getHeight: () => $target.actual('height'),
    getTabCount: () => 1
  }
}

/** Log performance timing for Morpheus dot plots and heatmaps */
PlotUtils.logMorpheusPerfTime = function(target, plotType, genes) {
  const graphId = target.slice(1) // e.g. #dotplot-1 -> dotplot-1
  performance.measure(graphId, `perfTimeStart-${graphId}`)
  const perfTime = Math.round(
    performance.getEntriesByName(graphId)[0].duration
  )

  log(`plot:${plotType}`, { perfTime, genes })
}

PlotUtils.dotPlotColorScheme = {
  // Blue, purple, red.  These red and blue hues are accessible, per WCAG.
  colors: ['#0000BB', '#CC0088', '#FF0000'],

  // TODO: Incorporate expression units, once such metadata is available.
  values: [0, 0.5, 1]
}


export default PlotUtils
