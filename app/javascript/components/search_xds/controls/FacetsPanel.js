import React from 'react'

import FacetControl from './FacetControl'
import CombinedFacetControl from './CombinedFacetControl'
import MoreFacetsButton from './MoreFacetsButton'

const defaultFacetIds = ['disease', 'species']
const moreFacetIds = [
  'sex', 'race', 'library_preparation_protocol', 'organism_age'
]

/**
 * Container for horizontal list of facet buttons, and "More Facets" button
 */
export default function FacetsPanel({ facets }) {
  const defaultFacets = facets.filter(facet => defaultFacetIds.includes(facet.id))
  const moreFacets = facets.filter(facet => moreFacetIds.includes(facet.id))
  return (
    <>
      <CombinedFacetControl controlDisplayName="cell type" facetIds={['cell_type', 'cell_type__custom']}/>
      <CombinedFacetControl controlDisplayName="organ" facetIds={['organ', 'organ_region']}/>
      {
        defaultFacets.map((facet, i) => {
          return <FacetControl facet={facet} key={i}/>
        })
      }
      <MoreFacetsButton facets={moreFacets} />
    </>
  )
}
