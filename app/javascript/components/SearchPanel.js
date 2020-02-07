import React from 'react';

import FacetControl from './FacetControl';
import MoreFacetsButton from './MoreFacetsButton';
import DownloadButton from './DownloadButton';
import KeywordSearch from './KeywordSearch';

// Only for development!  We'll fetch data once API endpoints are available.
import {facetsResponseMock, searchFiltersResponseMock} from './FacetsMockData';
const facets = facetsResponseMock;

const defaultFacetIDs = ['disease', 'organ', 'species', 'cell_type'];
const moreFacetIDs = ['sex', 'race', 'library_preparation_protocol', 'organism_age'];

const defaultFacets = facets.filter(facet => defaultFacetIDs.includes(facet.id));
const moreFacets = facets.filter(facet => moreFacetIDs.includes(facet.id));

window.searchFiltersResponse = searchFiltersResponseMock;

// const searchStyle= {
//   'font-size':'22px',
//   color: '#333F52'

// }
// const searchPanelStyle = {
//   borderRadius: '25px',
//   background: 'white'
// };
/**
 * Component for SCP advanced search UI
 *
 * This is the entry point into React code from the traditional JS code
 * See related integration at /app/javascript/packs/application.js
 */
function SearchPanel(props) {
  // Note:  Enventually this fuction will have State and will turn into a class component. There's room for this to become 
  // a higher order Component (HOC). This Search component is specific to the "Studies"
  // tab when it should be able to support the 'home' Seach Panel, Studies, Genes and Cells search panels.
  return (
    <div className='container-fluid' id='search-panel'>
      <KeywordSearch updateKeyword={props.updateKeyword}/>
      {
        defaultFacets.map((facet, i) => {
          return <FacetControl facet={facet} key={i}/>
        })
      }
      <MoreFacetsButton facets={moreFacets} />
      <DownloadButton />
    </div>
  );
}
export default SearchPanel;