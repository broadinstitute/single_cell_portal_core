import React from 'react';
import { Slider, Rail, Handles, Tracks, Ticks } from "react-compound-slider";
import InputGroup from 'react-bootstrap/InputGroup';

/**
 * Component for a list of string-based filters, e.g. disease, species
 */
function FilterList(props) {
  return (
    <ul>
    {
      props.facet.filters.map((filter) => {
        return (
          <li key={'li-' + filter.id}>
            <InputGroup.Checkbox
              id={filter.id}
              aria-label="Checkbox"
              name={filter.id}
            />
            <label htmlFor={filter.id}>{filter.name}</label>
          </li>
        );
      })
    }
    </ul>
  );
}

/**
 * Component for slider to filter numerical facets, e.g. organism age
 *
 * Stub, will develop.
 */
function FilterSlider(props) {
  const facet = props.facet;
  // React Compound Slider
  // API: https://react-compound-slider.netlify.com/docs
  // Examples: https://react-compound-slider.netlify.com/horizontal
  return (
    <li>
      <Slider
        domain={[facet.min, facet.max]}
      />
    </li>
  );
}

/**
 * Component for filter list and filter slider
 */
export default function Filters(props) {
  const facet = props.facet;
  if (facet.type === 'string') {
    return <FilterList facet={facet} />;
  } else {
    return <FilterSlider facet={facet} />;
  }
}
