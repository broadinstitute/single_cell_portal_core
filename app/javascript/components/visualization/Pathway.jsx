import React, { useState, useEffect } from 'react'

/**  */
export default function Pathway({
  studyAccession, cluster, annotation, genes, dimensions
}) {
  const pathwayId = genes[0]
  const pwDimensions = Object.assign({}, dimensions)

  pwDimensions.height -= 160
  console.log('dimensions', dimensions)
  useEffect(() => {
    window.Ideogram.drawPathway(pathwayId, '', '', '.pathway', pwDimensions)
  }, [genes.join(',')])

  const style = { width: dimensions.width, height: pwDimensions.height + 40 }

  return (
    <div className="pathway" style={style}>
    </div>
  )
}
