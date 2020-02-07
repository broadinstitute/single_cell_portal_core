import React from 'react';
import KeyWordSearch from './KeyWordSearch';
import Button from 'react-bootstrap/lib/Button';
// import FacetControl from './FacetControl';
// import MoreFiltersButton from './MoreFiltersButton';
import Grid from 'react-bootstrap/lib/Grid';
import Row from 'react-bootstrap/lib/Row';
import Col from 'react-bootstrap/lib/Col';
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

const searchStyle= {
  'font-size':'22px',
  color: '#333F52'

}
const searchPanelStyle = {
  borderRadius: '25px',
  background: 'white'
};
/**
 * Component for SCP advanced search UI
 *
 * This is the entry point into React code from the traditional JS code
 * See related integration at /app/javascript/packs/application.js
 */
function SearchPanel() {
  // Note:  Enventually this fuction will have State and will turn into a class component. There's room for this to become 
  // a higher order Component (HOC). This Search component is specific to the "Studies"
  // tab when it should be able to support the 'home' Seach Panel, Studies, Genes and Cells search panels.
  return (
    <div style={searchPanelStyle} className='container-fluid' id='search-panel'>
    <KeyWordSearch/>
      {/*
        defaultFacets.map((facet, i) => {
          return <FacetControl facet={facet} key={i}/>
        })
      */}
      {/* <MoreFacetsButton facets={moreFacets} />
      <DownloadButton /> */}
    </div>
  );
}

export default SearchPanel;
