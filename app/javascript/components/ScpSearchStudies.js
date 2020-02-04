import React from 'react';
import KeyWordSearch from './KeyWordSearch'
import FacetControl from './FacetControl';
import MoreFiltersButton from './MoreFiltersButton';

const facets = [
  {
    name: 'Species',
    filters: [
      {name: 'Human', id: 'NCBItaxon9606'},
      {name: 'Mouse', id: 'NCBItaxon10090'},
      {name: 'Cow', id: 'NCBItaxon5555'},
    ]
  },
  {
    name: 'Disease',
    filters: [
      {name: 'tubercolosis', id: 'DOID0000123'},
      {name: 'ocular tubercolosis', id: 'DOID0000123'},
      {name: 'tuberculosis, spinal', id: 'DOID0000123'},
      {name: 'endocrime tuberculosis', id: 'DOID0000123'},
      {name: 'inactive tuberculosis', id: 'DOID0000123'},
      {name: 'tubercolosis, bovine', id: 'DOID0000123'},
      {name: 'tuberculosis, avian', id: 'DOID0000123'},
      {name: 'esophageal tubercolosis', id: 'DOID0000123'},
      {name: 'intestinal tuberculosis', id: 'DOID0000123'},
      {name: 'abdominal tuberculosis', id: 'DOID0000123'},
    ]
  }
];

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
function ScpSearchStudies() {
  return (
    <div id='search-panel'>
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
