import React, { useContext } from 'react'
import { faSearch } from '@fortawesome/free-solid-svg-icons'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { getDisplayNameForFacet } from 'providers/SearchFacetProvider'
import { SearchSelectionContext } from 'providers/SearchSelectionProvider'
import Button from 'react-bootstrap/lib/Button'


function formattedJoinedList(itemTexts, itemClass, joinText) {
  return itemTexts.map((text, index) => {
    return (
      <span key={index}>
        <span className={itemClass}>{text}</span>
        { (index != itemTexts.length - 1) &&
            <span className="join-text">{joinText}</span>}
      </span>
    )
  })
}

function formatFacet(facet, index, numFacets) {
  let facetContent
  if (Array.isArray(facet.filters)) {
    facetContent = formattedJoinedList(facet.filters.map(filter => filter.name),
      'filter-name',
      ' OR ')
  } else { // it's a numeric facet
    facetContent = (<span className="filter-name">
      {facet.filters.min} - {facet.filters.max} {facet.filters.unit ? facet.filters.unit : '' }
    </span>)
  }
  return (
    <span key={index}>
      (<span className="facet-name">{getDisplayNameForFacet(facet.id)}: </span>
      { facetContent })
      { (index != numFacets - 1) &&
        <span className="join-text"> AND </span>}
    </span>
  )
}

export const ClearAllButton = () => {
  const selectionContext = useContext(SearchSelectionContext)
  const clearSearch = () => {
    const emptyFilters = {}
    Object.keys(selectionContext.facets
    ).forEach(facet => {
      emptyFilters[facet] = []
    })
    const emptySearchParams = {
      terms: '',
      facets: emptyFilters
    }
    selectionContext.updateSelection(emptySearchParams, true)
  }
  return (
    <Button onClick = {clearSearch}>Clear All</Button>)
}

export default function SearchQueryDisplay({ terms, facets }) {
  const hasFacets = facets && facets.length > 0
  const hasTerms = terms && terms.length > 0
  if (!hasFacets && !hasTerms) {
    return <></>
  }

  let facetsDisplay = <span></span>
  let termsDisplay = <span></span>

  if (hasFacets) {
    let FacetContainer = props => <>{props.children}</>
    if (hasTerms) {
      FacetContainer = function FacetText(props) {
        return (<>
          <span className="join-text"> AND </span>({props.children})
        </>)
      }
    }
    const facetElements = facets.map((facet, index) => formatFacet(facet, index, facets.length))
    facetsDisplay = <FacetContainer>Metadata contains {facetElements}</FacetContainer>
  }
  if (hasTerms) {
    termsDisplay = (
      <span>Text contains (
        { formattedJoinedList(terms, 'search-term', ' OR ') }
      )</span>)
    if (hasFacets) {
      termsDisplay = <span>({termsDisplay})</span>
    }
  }
  return (
    <div className="search-query">
      <FontAwesomeIcon icon={faSearch} />: <span className="query-text">{termsDisplay}{facetsDisplay}</span> <ClearAllButton/>
    </div>
  )
}
