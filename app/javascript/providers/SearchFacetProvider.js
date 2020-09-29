import React, { useContext, useState } from 'react'
import { fetchFacets } from 'lib/scp-api'

/*
 * this may evolve into something more sophisticated, or with actual
 * message keys, but for now it just converts snake case to word case
 * see https://broadworkbench.atlassian.net/browse/SCP-2108
 */
export function getDisplayNameForFacet(facetId) {
  return facetId.replace(/__|_/gi, ' ')
}

export const SearchFacetContext = React.createContext({
  facets: [],
  isLoading: false,
  isLoaded: false
})

export function useContextSearchFacet() {
  return useContext(SearchFacetContext)
}

export default function SearchFacetProvider(props) {
  const [facetState, setFacetState] = useState({
    facets: [],
    isLoading: false,
    isLoaded: false
  })
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
