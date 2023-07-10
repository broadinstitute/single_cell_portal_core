import React, { useState, useEffect } from 'react'

import noUiSlider from 'nouislider'
import 'nouislider/dist/nouislider.css'

/** Get display value for given metric */
function MetricDisplayValue({ metric }) {
  return (
    <>
      {metric === 'log2FoldChange' && <>log<sub>2</sub>(FC)</>}
      {metric === 'pvalAdj' && <>Adj. p-value</>}
      {metric === 'qval' && <>q-value</>}
    </>
  )
}

/**
  * Adds slider widget for a numerical metric
  **/
function SliderContainer({ metric }) {
  return (
    <div className="de-slider-container">
      <div className="de-slider-checkbox-container">
        <input type="checkbox" className="slider-checkbox" id={`slider-checkbox-${metric}`}/>
        <label htmlFor={`slider-checkbox-${metric}`} >
          <MetricDisplayValue metric={metric} />
        </label>
      </div>
      <div className={`de-slider de-slider-${metric}`}></div>
    </div>
  )
}

const defaultSliderConfigProps = {
  'pvalAdj': {
    range: {
      'min': [0, 0.001],
      '50%': [0.05, 0.01],
      'max': 1
    },
    start: [0, 0.05],
    sliderDecimals: 3,
    pipDecimals: 3,
    connect: true,
    values: [0, 25, 50, 73.5, 100],
    density: 4
  },
  'qval': {
    range: {
      'min': [0, 0.001],
      '50%': [0.05, 0.01],
      'max': 1
    },
    start: [0, 0.05],
    sliderDecimals: 3,
    pipDecimals: 3,
    connect: true,
    values: [0, 25, 50, 73.5, 100],
    density: 4
  },
  'log2FoldChange': {
    range: {
      'min': [-1.5],
      'max': 1.5
    },
    start: [-1.5, -0.26, 0.26, 1.5],
    sliderDecimals: 2,
    pipDecimals: 1,
    connect: [false, true, false, true, false],
    values: [0, 16.7, 34.4, 50, 66.7, 84.4, 100],
    density: 3
  }
}

/**
* Provides "noUiSlider" configuration object for the given metric
*
* noUiSlider docs: https://refreshless.com/nouislider/
**/
function getSliderConfig(metric, range) {
  const defaultProps = defaultSliderConfigProps[metric]

  const configRange = {
    max: range.shownMax,
    min: range.shownMin
  }

  const config = {
    range: configRange,

    // Handles start at ...
    start: defaultProps.start,

    connect: defaultProps.connect,

    // Move handle on tap, bars are draggable
    behaviour: 'tap-drag',
    tooltips: true,
    // format: sliderDecimals,

    // Show a scale with the slider
    pips: {
      mode: 'positions',
      values: defaultProps.values,
      stepped: true,
      density: defaultProps.density
      // format: pipDecimals
    }
  }

  console.log('config', config)
}

/** Get max and min for each metric among DE genes to show */
function getRanges(metrics, genesToShow) {
  const rangesByMetric = {}

  metrics.forEach(metric => {
    rangesByMetric[metric] = {
      max: 0,
      min: 0,
      shownMax: 0,
      shownMin: 0
    }
  })
  const numMetrics = metrics.length

  // Classic `for` loops for fastest performance
  for (let i = 0; i < genesToShow.length; i++) {
    const deGene = genesToShow[i]
    for (let j = 0; j < numMetrics; j++) {
      const metric = metrics[j]
      const value = deGene[metric]
      const range = rangesByMetric[metric]
      if (value < range.min) {
        // Minimum observed value
        rangesByMetric[metric].min = value
      } else if (value > range.max) {
        // Maximum observed value
        rangesByMetric[metric].max = value
      }
    }
  }

  // Make sliders with + _and_ - values symmetric in _shown_ range.
  // This accounts for and helps highlight skewed distributions.
  metrics.forEach(metric => {
    const min = rangesByMetric[metric].min
    const max = rangesByMetric[metric].max
    if (min < 0 && max > 0) {
      const absoluteMax = Math.abs(max)
      const absoluteMin = Math.abs(min)
      const isMaxAbsolutelyGreater = absoluteMax > absoluteMin
      const shownMax = isMaxAbsolutelyGreater ? max : absoluteMin
      const shownMin = !isMaxAbsolutelyGreater ? min : absoluteMax
      rangesByMetric[metric].shownMax = shownMax
      rangesByMetric[metric].shownMin = shownMin
    }
  })

  return rangesByMetric
}

/** Range filters for DE table */
export default function DifferentialExpressionFilters({ genesToShow, isAuthorDe }) {
  const fdrMetric = isAuthorDe ? 'qval' : 'pvalAdj'
  const metrics = ['log2FoldChange', fdrMetric]

  const rangesByMetric = getRanges(metrics, genesToShow)
  console.log('rangesByMetric', rangesByMetric)

  useEffect(() => {
    metrics.forEach(metric => {
      const slider = document.querySelector(`.de-slider-${metric}`)

      if (!slider.noUiSlider) {
        const range = rangesByMetric[metric]
        const config = getSliderConfig(metric, range)
        noUiSlider.create(slider, config)
      }
    })
  })

  return (
    <div>
      {metrics.map(metric => <><SliderContainer metric={metric} /><br/></>)}
    </div>
  )
}
