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

/**
* Provides "noUiSlider" configuration object for the given metric
*
* noUiSlider docs: https://refreshless.com/nouislider/
**/
function getSliderConfig(metric) {
  const props = {
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

  return {
    range: props[metric].range,

    // Handles start at ...
    start: props[metric].start,

    connect: props[metric].connect,

    // Move handle on tap, bars are draggable
    behaviour: 'tap-drag',
    tooltips: true,
    // format: sliderDecimals,

    // Show a scale with the slider
    pips: {
      mode: 'positions',
      values: props[metric].values,
      stepped: true,
      density: props[metric].density
      // format: pipDecimals
    }
  }
}

/** Range filters for DE table */
export default function DifferentialExpressionFilters(genesToShow, isAuthorDe) {
  const fdrMetric = isAuthorDe ? 'qval' : 'pvalAdj'
  const metrics = ['log2FoldChange', fdrMetric]
  useEffect(() => {
    metrics.forEach(metric => {
      const slider = document.querySelector(`.de-slider-${metric}`)

      if (!slider.noUiSlider) {
        noUiSlider.create(slider, getSliderConfig(metric))
      }
    })
  })

  return (
    <div>
      {metrics.map(metric => <><SliderContainer metric={metric} /><br/></>)}
    </div>
  )
}
