import React from 'react'
import PanelGroup from 'react-bootstrap/lib/PanelGroup'

import FacetControl from './FacetControl'

/**
 * Expandable sections for facets in "More facets" popup
 */
export default function FacetsAccordion(props) {
  return (
    <PanelGroup accordion id='facets-accordion'>
      {
        props.facets.map((facet, i) => {
          return (
            <FacetControl facet={facet} key={i}/>
          )
        })
      }
    </PanelGroup>
  )
}
