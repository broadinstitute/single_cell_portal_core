import React from 'react';
import Facet from './Facet';
import KeyWordSearch from './KeyWordSearch'

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

const studies = [
  {
    name: 'Single nucleus RNA-seq',
    cells: 5426,
    id: 'SCP1',
    body: 'orem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.',
  },
  {
    name: 'Single nucleus RNA-seq',
    cells: 5426,
    id: 'SCP2',
    body: 'orem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.',
  },
  {
    name: 'Single nucleus RNA-seq',
    cells: 5426,
    id: 'SCP3',
    body: 'orem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.',
  },
  {
    name: 'Single nucleus RNA-seq',
    cells: 5426,
    id: 'SCP4',
    body: 'orem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.',
  },
  {
    name: 'Single nucleus RNA-seq',
    cells: 5426,
    id: 'SCP5',
    body: 'orem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industrys standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum.',
  },
];
function SearchPanel() {
  const tabTitle = "Studies"
  return (
    <div className="ScpSearch">
    <div><KeyWordSearch/></div>
      {
        facets.map((facet) => {
          return <Facet facet={facet} />
        })
      }
    </div>
  );
}

export default SearchPanel;