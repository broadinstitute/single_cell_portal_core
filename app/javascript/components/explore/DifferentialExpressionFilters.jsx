import React, { useEffect } from 'react'

import noUiSlider from 'nouislider'
import 'nouislider/dist/nouislider.css'
import wNumb from 'wnumb'

/** Get display value for given metric */
function MetricDisplayValue({ metric }) {
  return (
    <>
      {metric === 'log2FoldChange' && <>log<sub>2</sub>(FC)</>}
      {metric === 'pvalAdj' && <>Adj. p-value</>}
      {metric === 'pval' && <>p-value</>}
      {metric === 'qval' && <>q-value</>}
    </>
  )
}

/**
  * Adds slider widget for a numerical metric
  **/
function SliderContainer({ metricHeader, metric, toggleDeFacet, isActive }) {
  return (
    <div className={`de-slider-container ${isActive ? '' : 'inactive'}`}>
      <div className="de-slider-checkbox-container">
        <input
          type="checkbox"
          checked={isActive}
          className={`slider-checkbox slider-checkbox-${metricHeader}`}
          onChange={() => {toggleDeFacet(metricHeader)}}
        />
        <label htmlFor={`slider-checkbox-${metricHeader}`} >
          <MetricDisplayValue metric={metric} />
        </label>
      </div>
      <div className={`de-slider de-slider-${metricHeader}`} data-metric-header={metricHeader}></div>
      <br/>
    </div>
  )
}

const defaultSliderConfigProps = {
  'significance': {
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
  'size': {
    range: {
      'min': [-1.5],
      'max': 1.5
    },
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
function getSliderConfig(metricHeader) {
  const defaultProps = defaultSliderConfigProps[metricHeader]

  let configRange
  let configStart
  if (metricHeader === 'significance') {
    configRange = {
      'min': [0, 0.001],
      '50%': [0.05, 0.01],
      'max': 1
    }
    configStart = [0, 0.05]
  } else {
    configRange = {
      'min': [-1.5],
      'max': 1.5
    },
    configStart = [-1.5, -0.26, 0.26, 1.5]
  }

  const pipDecimals = wNumb({ decimals: defaultProps.pipDecimals })

  const sliderDecimals = wNumb({ decimals: defaultProps.sliderDecimals })

  const config = {
    range: configRange,

    // Handles start at ...
    start: configStart,

    connect: defaultProps.connect,

    // Move handle on tap, bars are draggable
    behaviour: 'tap-drag',
    tooltips: true,
    format: sliderDecimals,

    // Show a scale with the slider
    pips: {
      mode: 'positions',
      values: defaultProps.values,
      stepped: true,
      density: defaultProps.density,
      format: pipDecimals
    }
  }

  return config
}

/** Range filters for DE table */
export default function DifferentialExpressionFilters({
  deFacets, activeFacets, updateDeFacets, toggleDeFacet,
  hasPairwiseDe, sizeMetric, significanceMetric
}) {
  const metricHeaders = ['size', 'significance']
  const metrics = [sizeMetric, significanceMetric]

  /** Update DE facets upon changing range filter selection */
  function onUpdateDeFacets(range) {
    // eslint-disable-next-line no-invalid-this
    const slider = this
    const metricHeader = slider.target.dataset['metricHeader']

    range = range.map(d => parseFloat(d))
    if (metricHeader === 'size') {
      range = range.map(v => {
        if (v === -1.5) {return -Infinity}
        if (v === 1.5) {return Infinity}
        return v
      })
      range = [{ min: range[0], max: range[1] }, { min: range[2], max: range[3] }]
    } else {
      range = [{ min: range[0], max: range[1] }]
    }
    deFacets[metricHeader] = range

    updateDeFacets(deFacets, metricHeader)
  }

  useEffect(() => {
    metricHeaders.forEach(metricHeader => {
      const sliderSelector = `.de-slider-${metricHeader}`
      const slider = document.querySelector(sliderSelector)

      if (!slider.noUiSlider) {
        const config = getSliderConfig(metricHeader)
        noUiSlider.create(slider, config)
        if (metricHeader === 'size') {
          const val1 = document.querySelector(`${sliderSelector} .noUi-value:nth-child(2)`)
          val1.innerHTML = `≤ ${ val1.innerHTML}`
          const val2 = document.querySelector(`${sliderSelector} .noUi-value:last-child`)
          val2.innerHTML = `≥ ${ val2.innerHTML}`
        }
        slider.noUiSlider.on('change', onUpdateDeFacets)
      }
    })
  })

  return (
    <div>
      {!hasPairwiseDe && <br/>}
      {metricHeaders.map((metricHeader, i) =>
        <SliderContainer
          metricHeader={metricHeader}
          metric={metrics[i]}
          key={metricHeader}
          toggleDeFacet={toggleDeFacet}
          isActive={activeFacets[metricHeader]}
        />
      )}
    </div>
  )
}
