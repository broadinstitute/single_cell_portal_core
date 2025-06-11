import React from 'react'
import PanelGroup from 'react-bootstrap/lib/PanelGroup'

import FacetControl from './FacetControl'
import OptionsControl from '~/components/search/controls/OptionsControl'

/**
 * Expandable sections for facets in "More facets" popup
 */
export default function FacetsAccordion(props) {
  const optionsControl = <OptionsControl
    searchContext={props.searchContext} searchProp='external' value='hca' label='Include HCA results'/>
  return (
    <PanelGroup accordion id='facets-accordion'>
      {
        props.facets.map((facet, i) => {
          return (
            <FacetControl facet={facet} key={i}/>
          )
        })
      }
      { optionsControl }
    </PanelGroup>
  )
}
