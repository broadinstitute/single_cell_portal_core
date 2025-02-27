import React, { useState, useEffect } from 'react'
import { manageDrawPathway } from '~/lib/pathway-expression'

/**  */
export default function Pathway({
  studyAccession, cluster, annotation, genes, dimensions
}) {
  const pathwayId = genes[0]
  const pwDimensions = Object.assign({}, dimensions)

  pwDimensions.height -= 80
  pwDimensions.width -= 200

  manageDrawPathway(studyAccession, cluster, annotation)

  useEffect(() => {
    window.Ideogram.drawPathway(pathwayId, '', '', '.pathway', pwDimensions, false)
  }, [cluster, annotation, genes.join(',')])

  const style = { width: pwDimensions.width, height: pwDimensions.height + 600 }

  return (
    <div className="pathway" style={style}>
    </div>
  )
}
