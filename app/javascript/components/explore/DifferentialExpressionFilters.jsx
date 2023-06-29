import React, { useState, useEffect } from 'react'

import noUiSlider from 'nouislider'
import 'nouislider/dist/nouislider.css'

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

  return (
    <div>
      <div className="de-slider"></div>
      <br/>
    </div>
  )
}
