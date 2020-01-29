
// Proposed API endpoint: GET /facets
export const facetsResponseMock = [
  {
    name: 'Species',
    id: 'species',
    links: [{name: 'NCBI Taxonomy', url: 'https://foo.tdb'}],
    filters: [
      {name: 'human', id: 'NCBItaxon9606'},
      {name: 'mouse', id: 'NCBItaxon10090'},
      {name: 'cow', id: 'NCBItaxon5555'},
    ]
  },
  {
    name: 'Disease',
    id: 'disease',
    links: [
      {name: 'Disease Ontology', url: 'https://bar.tdb'},
      {name: 'PATO Ontology', url: 'https://pato.tdb'},
    ],
    filters: [
      {name: 'Tubercolosis', id: 'DOID0000123'},
      {name: 'Ocular tubercolosis', id: 'DOID0000124'},
      {name: 'Tuberculosis, spinal', id: 'DOID0000125'},
    ]
  },
  {
    name: 'Organ',
    id: 'organ',
    links: [{name: 'UBERON', url: 'https://uberon.tbd'}],
    filters: [
      {name: 'Brain', id: 'UBERON000123'},
      {name: 'Heart', id: 'UBERON000124'},
      {name: 'Skeletal muscle', id: 'UBERON000125'},
      {name: 'PBMC', id: 'UBERON000126'},
    ]
  }
];

// Proposed API endpoint: GET /search-filters?facet=disease&query=tuberculosis
export const searchFiltersResponseMock = {
  facet: 'disease',
  query: 'tuberculosis',
  filters: [
    {name: 'Tubercolosis', id: 'DOID0000123'},
    {name: 'Ocular tubercolosis', id: 'DOID0000124'},
    {name: 'Tuberculosis, spinal', id: 'DOID0000125'},
    {name: 'Endocrine tuberculosis', id: 'DOID0000126'},
    {name: 'Inactive tuberculosis', id: 'DOID0000127'},
    {name: 'Tubercolosis, bovine', id: 'DOID0000128'},
    {name: 'Tuberculosis, avian', id: 'DOID0000129'},
    {name: 'Esophageal tubercolosis', id: 'DOID0000130'},
    {name: 'Intestinal tuberculosis', id: 'DOID0000131'},
    {name: 'Abdominal tuberculosis', id: 'DOID0000132'},
  ]
};