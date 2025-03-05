import React, { useState, useEffect } from 'react'
import { manageDrawPathway } from '~/lib/pathway-expression'
// import { getPathwayName, getPathwayIdsByName } from '~/lib/search-utils'
import { getIdentifierForAnnotation } from '~/lib/cluster-utils'

/**  */
export default function Pathway({
  studyAccession, cluster, annotation, pathway, dimensions
}) {
  const pathwayId = pathway
  const pwDimensions = Object.assign({}, dimensions)

  pwDimensions.height -= 80
  pwDimensions.width -= 200

  manageDrawPathway(studyAccession, cluster, annotation)

  // Stringify object, to enable tracking state change
  const annotationId = getIdentifierForAnnotation(annotation)

  useEffect(() => {
    window.Ideogram.drawPathway(pathwayId, '', '', '.pathway', pwDimensions, false)
  }, [cluster, annotationId, pathway])

  const style = { width: pwDimensions.width, height: pwDimensions.height + 600 }

  return (
    <div className="pathway" style={style}>
    </div>
  )
}
