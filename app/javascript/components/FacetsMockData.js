
/**
 * This mock data is imported by ScpSearchStudies.js and used
 * to populate the search UI for the prototype.
 *
 * The data structures are quickly evolving drafts.
 */

// Proposed API endpoint: GET /facets
export const facetsResponseMock = [
  {
    name: 'Disease',
    id: 'disease',
    type: 'array',
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
    type: 'string',
    links: [{name: 'UBERON', url: 'https://uberon.tbd'}],
    filters: [
      {name: 'Brain', id: 'UBERON000123'},
      {name: 'Heart', id: 'UBERON000124'},
      {name: 'Skeletal muscle', id: 'UBERON000125'},
      {name: 'PBMC', id: 'UBERON000126'},
    ]
  },
  {
    name: 'Species',
    id: 'species',
    type: 'string',
    links: [{name: 'NCBI Taxonomy', url: 'https://foo.tdb'}],
    filters: [
      {name: 'Human', id: 'NCBItaxon9606'},
      {name: 'Mouse', id: 'NCBItaxon10090'},
      {name: 'Cow', id: 'NCBItaxon5555'},
    ]
  },
  {
    name: 'Cell Type',
    id: 'cell_type',
    type: 'string',
    links: [{name: 'Cell Line Ontology', url: 'https://clo.tdb'}],
    filters: [
      {name: 'Macrophage', id: 'CLO0000123'},
      {name: 'Lymphocyte', id: 'CLO0000124'},
      {name: 'Mast cell', id: 'CLO0000125'},
    ]
  },
  {
    name: 'Sex',
    id: 'sex',
    links: [],
    type: 'string',
    filters: [
      {name: 'female', id: 'SCPO00001'},
      {name: 'male', id: 'SCPO00002'},
      {name: 'mixed', id: 'SCPO00003'},
      {name: 'unknown', id: 'SCPO00004'},
    ]
  },
  {
    name: 'Race',
    id: 'race',
    type: 'string',
    links: [],
    filters: [
      {name: 'Foo', id: 'SCPO00004'},
      {name: 'Bar', id: 'SCPO00005'},
      {name: 'Baz', id: 'SCPO00006'},
    ]
  },
  {
    name: 'Library Preparation Protocol',
    id: 'library_preparation_protocol',
    type: 'string',
    links: [],
    filters: [
      {name: 'Foo', id: 'SCPO00004'},
      {name: 'Bar', id: 'SCPO00005'},
      {name: 'Baz', id: 'SCPO00006'},
    ]
  },
  {
    name: 'Organism Age',
    id: 'organism_age',
    links: [],
    type: 'number',
    max: '130',
    min: '0',
    unit: 'years'
  },
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
