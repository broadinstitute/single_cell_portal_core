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
    <div style={{ marginBottom: '115px', marginLeft: '15px' }}>
      <div style={{ marginLeft: '-15px', zIndex: '2' }}>
        <input type="checkbox" className="slider-checkbox" id={`slider-checkbox-${metric}`}/>
        <label htmlFor={`slider-checkbox-${metric}`}>
          <MetricDisplayValue metric={metric} />
        </label>
      </div>
      {/* <div id="${sliderId}" className="ideogramSlider" style="top: 40px"></div> */}

      <div className={`de-slider-${metric}`}></div>
    </div>
  )
}

/** Range filters for DE table */
export default function DifferentialExpressionFilters(genesToShow) {
  const metrics = ['log2FoldChange', 'pvalAdj']
  useEffect(() => {
    metrics.forEach(metric => {
      const slider = document.querySelector(`.de-slider-${metric}`)

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
  })

  return (
    <div>
      <SliderContainer metric='log2FoldChange' />
      <SliderContainer metric='pvalAdj' />
      <br/>
    </div>
  )
}
