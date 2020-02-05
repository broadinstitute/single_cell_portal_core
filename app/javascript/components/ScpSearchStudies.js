import React from 'react';
import KeyWordSearch from './KeyWordSearch';
import FacetControl from './FacetControl';
import MoreFiltersButton from './MoreFiltersButton';
import Grid from 'react-bootstrap/lib/Grid';
import Row from 'react-bootstrap/lib/Row';
import { faNewspaper, faChevronLeft } from "@fortawesome/free-solid-svg-icons";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";

// Only for development!  We'll fetch data once API endpoints are available.
import {facetsResponseMock, searchFiltersResponseMock} from './FacetsMockData';
const facets = facetsResponseMock;

const defaultFacetIDs = ['disease', 'organ', 'species', 'cell_type'];
const moreFacetIDs = ['sex', 'race', 'library_preparation_protocol', 'organism_age'];

const defaultFacets = facets.filter(facet => defaultFacetIDs.includes(facet.id));
const moreFacets = facets.filter(facet => moreFacetIDs.includes(facet.id));

window.searchFiltersResponse = searchFiltersResponseMock;

/**
 * Component for SCP advanced search UI
 *
 * This is the entry point into React code from the traditional JS code
 * See related integration at /app/javascript/packs/application.js
 */
function SearchPanel() {
  return (
    <div id='search-panel'>
      <div>
      <button><FontAwesomeIcon icon={faChevronLeft} /></button>
        <FontAwesomeIcon icon={faNewspaper} />
        <h3>Studies</h3>
        </div>
    <KeyWordSearch/>
      {
        defaultFacets.map((facet) => {
          return <FacetControl facet={facet} />
        })
      }
      <MoreFiltersButton facets={moreFacets} />
    </div>
  );
}

export default SearchPanel;
