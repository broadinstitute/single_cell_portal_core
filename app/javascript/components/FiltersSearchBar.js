import React, { useState } from 'react';
import Form from 'react-bootstrap/lib/Form';
import FormControl from 'react-bootstrap/lib/FormControl';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faSearch } from '@fortawesome/free-solid-svg-icons';
import Button from 'react-bootstrap/lib/Button';

import { fetchFacetsFilters } from 'lib/scp-api';

/**
 * Component to search filters within a given facet
 * Used when facet has many available filters (e.g. disease)
 *
 * Stub, will develop.
 */
export default function FiltersSearchBar(props) {

  const [matchingFilters, setMatchingFilters] = useState([]);

  const componentName = 'filters-search-bar';
  const filtersSearchBarID = `${componentName}-${props.filtersBoxID}`;

  // Search for filters in this facet that match input text terms
  //
  // For example, among the many filters in the "Disease" facet, search
  // for filters matching the term "tuberculosis".
  async function searchFilters(terms) {
    const apiData = await fetchFacetsFilters(props.facetID, terms);
    const matchingFilters = apiData.filters;
    setMatchingFilters(matchingFilters);
  }

  async function handleSubmit(event) {
    event.preventDefault();
    const terms = event.target.elements[filtersSearchBarID].value;
    await searchFilters(terms);
  }

  async function handleSearchButtonClick(event) {
    const terms = event.parentElement.parentElement.elements[filtersSearchBarID].value;
    await searchFilters(terms);
  }

  return (
    <div class="filters-search-bar">
      <Form onSubmit={handleSubmit}>
        <FormControl
          id={filtersSearchBarID}
          className={componentName}
          type="text"
          placeholder="Search"
        />
        <Button className='search-button' onClick={handleSearchButtonClick}>
          <FontAwesomeIcon icon={faSearch}/>
        </Button>
      </Form>
    </div>
  );
}
