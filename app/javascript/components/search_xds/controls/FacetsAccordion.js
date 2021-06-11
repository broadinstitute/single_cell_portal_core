import React from 'react'
import PanelGroup from 'react-bootstrap/lib/PanelGroup'

import FacetControl from './FacetControl'

const defaultFacetIds = ['disease', 'species', 'organ', 'cell type']

/**
 * Expandable sections for facets in "More Facets" popup
 */
export default function FacetsAccordion(props) {
  return (
    <PanelGroup accordion id='facets-accordion'>
      {
        props.facets.map((facet, i) => {
          if (defaultFacetIds.includes(facet.id)) {
            return (
              <FacetControl facet={facet} key={i}/>
            )
          }
        })
      }
    </PanelGroup>
  )
}
