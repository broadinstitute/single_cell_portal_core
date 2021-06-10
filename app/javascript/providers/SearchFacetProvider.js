import React, { useState } from 'react'
import { fetchFacets } from 'lib/scp-api'

/**
 * this may evolve into something more sophisticated, or with actual
 * message keys, but for now it just converts snake case to word case
 * see https://broadworkbench.atlassian.net/browse/SCP-2108
 */
export function getDisplayNameForFacet(facetId) {
  const spaced = facetId.replace(/__|_/gi, ' ')

  // E.g. "cell type" -> "Cell type"
  return spaced[0].toUpperCase() + spaced.substring(1)
}

/** context for the list of facets loaded from the server */
export const SearchFacetContext = React.createContext({
  facets: [],
  isLoading: false,
  isLoaded: false
})

/** component which handles fetching search facets from the server and attaching them to a context */
export default function SearchFacetProvider(props) {
  const [facetState, setFacetState] = useState({
    facets: [],
    isLoading: false,
    isLoaded: false
  })
  /** fetch the facet list from the server */
  async function updateFacets() {
    setFacetState({
      facets: [],
      isLoading: true,
      isLoaded: false
    })
    const facets = await fetchFacets()
    setFacetState({
      facets,
      isLoading: false,
      isLoaded: true
    })
  }
  if (!facetState.isLoading && !facetState.isLoaded) {
    updateFacets()
  }
  return (
    <SearchFacetContext.Provider value={facetState}>
      { props.children }
    </SearchFacetContext.Provider>
  )
}
