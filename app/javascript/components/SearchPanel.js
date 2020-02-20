import React, { useState, useEffect } from 'react';

import KeywordSearch from './KeywordSearch';
import FacetControl from './FacetControl';
import MoreFacetsButton from './MoreFacetsButton';
import DownloadButton from './DownloadButton';

import { fetchFacets } from 'lib/scp-api';

const defaultFacetIds = ['disease', 'organ', 'species', 'cell_type'];
const moreFacetIds = ['sex', 'race', 'library_preparation_protocol', 'organism_age'];

/**
 * Component for SCP faceted search UI
 *
 * This is the entry point into React code from the traditional JS code
 * See related integration at /app/javascript/packs/application.js
 */
export default function SearchPanel(props) {
  // Note: This might become  a Higher-Order Component (HOC).
  // This search component is currently specific to the "Studies" tab, but
  // could possibly also enable search for "Genes" and "Cells" tabs.

  const [defaultFacets, setDefaultFacets] = useState([]);
  const [moreFacets, setMoreFacets] = useState([]);

  useEffect(() => {
    const fetchData = async () => {
      const facets = await fetchFacets(true);
      const df = facets.filter(facet => defaultFacetIds.includes(facet.id));
      const mf = facets.filter(facet => moreFacetIds.includes(facet.id));
      setDefaultFacets(df);
      setMoreFacets(mf);
    };
    fetchData();
  }, []);

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
