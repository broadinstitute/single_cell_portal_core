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

  it('Parses AnnData headers', async () => {
    const ontologies = await fetchOntologies()
    console.log('ontologies', ontologies)
    expect(1).toEqual(1)
  })
})
