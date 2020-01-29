import React from 'react';
import Facet from './Facet';
import SearchBar from './KeyWordSearch'

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