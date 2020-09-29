import React, { useContext } from 'react'
import { faSearch } from '@fortawesome/free-solid-svg-icons'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { getDisplayNameForFacet } from 'providers/SearchFacetProvider'
import { SearchSelectionContext } from 'providers/SearchSelectionProvider'
import Button from 'react-bootstrap/lib/Button'
import _flatten from 'lodash/flatten'


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

// Note that this logic needs to be kept in sync with the logic in generate_bq_query_string
const orFacets = [['cell_type', 'cell_type__custom'], ['organ', 'organ_region']]
const leadingOrFacets = orFacets.map(f => f[0])
const trailingOrFacets = orFacets.map(f => f[1])

function formatFacet(facet, index, numFacets, facets) {
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
  let joinText = ' AND '
  let leadingParens = '('
  let trailingParens = ')'
  const leadingOrGroupIndex = leadingOrFacets.indexOf(facet.id)
  if (leadingOrGroupIndex >= 0 &&
      index < numFacets - 1 &&
      trailingOrFacets[leadingOrGroupIndex] === facets[index + 1].id) {
    joinText = ' OR '
    leadingParens = '(('
  }
  const trailingOrGroupIndex = trailingOrFacets.indexOf(facet.id)
  if (trailingOrGroupIndex >= 0 &&
      index > 0 &&
      leadingOrFacets[trailingOrGroupIndex] === facets[index - 1].id) {
    trailingParens = '))'
  }
  return (
    <span key={index}>
      {leadingParens}<span className="facet-name">{getDisplayNameForFacet(facet.id)}: </span>
      { facetContent }{trailingParens}
      { (index != numFacets - 1) &&
        <span className="join-text">{joinText}</span>}
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
    // sort the facets so that OR'ed facets will be next to each other
    const flatOrFacets = _flatten(orFacets)
    const sortedFacets = facets.sort((f1, f2) => {
      const f1index = flatOrFacets.indexOf(f1.id)
      const f2index = flatOrFacets.indexOf(f2.id)
      return Math.sign(f1index - f2index)
    })
    let FacetContainer = props => <>{props.children}</>
    if (hasTerms) {
      FacetContainer = function FacetText(props) {
        return (<>
          <span className="join-text"> AND </span>({props.children})
        </>)
      }
    }
    const facetElements = sortedFacets.map((facet, index) => formatFacet(facet, index, sortedFacets.length, sortedFacets))
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
