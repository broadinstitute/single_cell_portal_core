const fetch = require('node-fetch')

import { metadataSchema } from 'lib/validation/shared-validation'
import {
  fetchOntologies, getOntologyShortNames, getOntologyBasedProps
} from 'lib/validation/ontology-validation'

import {
  nodeCaches, nodeHeaders, nodeRequest, nodeResponse
} from './node-web-api'

describe('Client-side file validation for AnnData', () => {
  const expectedOntologyNames = ['cl', 'uo', 'mondo', 'pato', 'hancestro', 'efo', 'uberon', 'ncbitaxon']
  beforeAll(() => {
    global.fetch = fetch

    global.caches = nodeCaches;
    global.Response = nodeResponse
    global.Request = nodeRequest
    global.Headers = nodeHeaders
  })

  it('Parses minified ontologies', async () => {
    const ontologies = await fetchOntologies()
    expect(Object.keys(ontologies)).toEqual(expectedOntologyNames)
    const expectedSpeciesNames = ['Homo sapiens', 'human']
    expect(ontologies.ncbitaxon['NCBITaxon_9606']).toEqual(expectedSpeciesNames)
  })

  it('finds all ontology-based metadata properties', () => {
    const propNames = Object.keys(metadataSchema.properties).filter(p => {
      return p !== 'organ_region' && metadataSchema.properties[p].ontology
    })
    const ontologyProps = getOntologyBasedProps()
    expect(propNames).toEqual(ontologyProps)
  })

  it('loads all ontology shortnames', () => {
    const shortNames = getOntologyShortNames()
    expect(shortNames).toEqual(expectedOntologyNames)
  })
})
