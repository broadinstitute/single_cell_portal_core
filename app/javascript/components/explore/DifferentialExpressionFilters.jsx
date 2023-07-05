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
  // const metricId = metric.replace(/\./g, '')
  // const sliderId = `${metricId }-${ comparisonId}`
  // const metricLabel = metricLabels[metric]
  return (
    <div style="margin-bottom: 115px; margin-left: 15px;">
      <div style="margin-left: -15px; z-index: 2;">
        <input type="checkbox" className="slider-checkbox" id="slider-checkbox-${sliderId}"/>
        <label htmlFor="slider-checkbox-${sliderId}">
          <MetricDisplayValue metric={metric} />
        </label>
      </div>
      <div id="${sliderId}" className="ideogramSlider" style="top: 40px"></div>
    </div>
  )
}

/** Range filters for DE table */
export default function DifferentialExpressionFilters(genesToShow) {
  useEffect(() => {
    const slider = document.querySelector('.de-slider')

    if (!slider.noUiSlider) {
      noUiSlider.create(slider, {
        start: [20, 80],
        connect: true,
        range: {
          'min': 0,
          'max': 100
        }
      })
    }
  })

  const metric = 'log2FoldChange'

  return (
    <div>
      <SliderContainer metric={metric}
      <div className="de-slider"></div>
      <br/>
    </div>
  )
}
