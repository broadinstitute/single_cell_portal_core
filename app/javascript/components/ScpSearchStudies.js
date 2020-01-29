import React from 'react';
import Facet from './Facet';
import SearchBar from './KeyWordSearch'

// Only for development!  We'll fetch data once API endpoints are available.
import {facetsResponseMock, searchFiltersResponseMock} from './FacetsMockData';
const facets = facetsResponseMock;

window.searchFiltersResponse = searchFiltersResponseMock;

function ScpSearchStudies() {
  return (
    <div className="ScpSearch">
    <div><SearchBar/></div> 
      {
        facets.map((facet) => {
          return <Facet facet={facet} />
        })
      }
    </div>
  );
}

export default ScpSearchStudies;