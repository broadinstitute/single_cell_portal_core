const fetch = require('node-fetch')

import {
  fetchOntologies
} from 'lib/validation/ontology-validation'

import {
  nodeCaches, nodeHeaders, nodeRequest, nodeResponse
} from './node-web-api'

describe('Client-side file validation for AnnData', () => {
  beforeAll(() => {
    global.fetch = fetch

    global.caches = nodeCaches;
    global.Response = nodeResponse
    global.Request = nodeRequest
    global.Headers = nodeHeaders
  })

  it('Parses minified ontologies', async () => {
    const ontologies = await fetchOntologies()
    const expectedOntologyNames = ['mondo', 'pato', 'efo', 'uberon', 'ncbitaxon']
    expect(Object.keys(ontologies)).toEqual(expectedOntologyNames)
    const expectedSpeciesNames = ['Homo sapiens', 'human']
    expect(ontologies.ncbitaxon['NCBITaxon_9606']).toEqual(expectedSpeciesNames)
  })
})
