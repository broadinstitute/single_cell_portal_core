import React from 'react'
import { faArrowsAltV, faArrowsAltH, faArrowsAlt } from '@fortawesome/free-solid-svg-icons'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'

const PlotOptions = function() {
  return 'placeholder component'
}

PlotOptions.ROW_CENTERING_OPTIONS = [
  { label: 'None', value: '' },
  { label: 'Z-score [(v - mean) / stdev]', value: 'z-score' },
  { label: 'Robust z-score [(v - median) / MAD]', value: 'robust z-score' }
]

PlotOptions.DEFAULT_ROW_CENTERING = ''

PlotOptions.FIT_OPTIONS = [
  { label: <span>None</span>, value: '' },
  { label: <span><FontAwesomeIcon icon={faArrowsAltV}/> Rows</span>, value: 'rows' },
  { label: <span><FontAwesomeIcon icon={faArrowsAltH}/> Columns</span>, value: 'cols' },
  { label: <span><FontAwesomeIcon icon={faArrowsAlt}/> Both</span>, value: 'both' }
]
PlotOptions.DEFAULT_FIT = ''

// sourced from https://github.com/plotly/plotly.js/blob/master/src/components/colorscale/scales.js
PlotOptions.SCATTER_COLOR_OPTIONS = [
  'Greys', 'YlGnBu', 'Greens', 'YlOrRd', 'Bluered', 'RdBu', 'Reds', 'Blues', 'Picnic',
  'Rainbow', 'Portland', 'Jet', 'Hot', 'Blackbody', 'Earth', 'Electric', 'Viridis', 'Cividis'
]

PlotOptions.defaultScatterColor = 'Viridis'

PlotOptions.dotPlotColorScheme = {
  // Blue, purple, red.  These red and blue hues are accessible, per WCAG.
  colors: ['#0000BB', '#CC0088', '#FF0000'],

  values: [0, 0.5, 1]
}


PlotOptions.DISTRIBUTION_PLOT_OPTIONS = [
  { label: 'Violin plot', value: 'violin' },
  { label: 'Box plot', value: 'box' }
]
PlotOptions.defaultDistributionPlot = PlotOptions.DISTRIBUTION_PLOT_OPTIONS[0].value

PlotOptions.DISTRIBUTION_POINTS_OPTIONS = [
  { label: 'None', value: 'none' },
  { label: 'All', value: 'all' },
  { label: 'Outliers', value: 'outliers' },
  { label: 'Suspected outliers', value: 'suspectedoutliers' }
]
PlotOptions.defaultDistributionPoints = PlotOptions.DISTRIBUTION_POINTS_OPTIONS[0].value

export default PlotOptions
