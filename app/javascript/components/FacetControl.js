import React, { useState } from 'react';
import FiltersBox from './FiltersBox';

/**
 * Converts string value to lowercase, hyphen-delimited version
 * e.g. "Cell type" -> "cell-type"
 */
function slug(value) {
  return value.toLowerCase().replace(/ /g, '-');
}

export default function FacetControl(props) {

  const [showFilters, setShowFilters] = useState(false);

  const facetName = props.facet.name;
  const facetId = `facet-${slug(facetName)}`;

  function handleClick() {
    setShowFilters(!showFilters);
  }

  return (
      <span
        id={facetId}
        className={`facet ${showFilters ? 'active' : ''}`}>
        <span
          onClick={handleClick}>
          {facetName}
        </span>
        <FiltersBox show={showFilters} facet={props.facet} />
      </span>
    );

}
