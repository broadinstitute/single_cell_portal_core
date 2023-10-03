import * as ScpApi from 'lib/scp-api'

import _cloneDeep from 'lodash/cloneDeep'
import { createCache } from 'components/explore/plot-data-cache'

// models a real response from api/v1/visualization/clusters
const FETCH_CLUSTER_RESPONSE = {
  data: {
    annotations: ['foo', 'bar'],
    cells: ['A', 'B'],
    x: [11, 14],
    y: [0, 1]
  },
  pointSize: 3,
  userSpecifiedRanges: null,
  showClusterPointBorders: false,
  description: null,
  is3D: false,
  isSubsampled: false,
  isAnnotatedScatter: false,
  numPoints: 130,
  axes: {
    titles: {
      x: 'X',
      y: 'Y',
      z: 'Z',
      magnitude: 'Expression'
    },
    aspects: null
  },
  hasCoordinateLabels: false,
  coordinateLabels: [],
  pointAlpha: 1,
  cluster: 'cluster.tsv',
  genes: [],
  annotParams: {
    name: 'buzzwords',
    type: 'group',
    scope: 'study',
    values: ['foo', 'bar'],
    identifier: 'biosample_id--group--study'
  },
  subsample: 'all',
  consensus: null
}

const CACHE_PERF_PARAMS = {
  legacyBackend: 0,
  parse: 0,
  url: 'cache'
}


const ANNOTATION_ONLY_RESPONSE = _cloneDeep(FETCH_CLUSTER_RESPONSE)
ANNOTATION_ONLY_RESPONSE.annotParams = {
  name: 'species',
  type: 'group',
  scope: 'study',
  values: ['dog', 'cat'],
  identifier: 'species--group--study'
}
ANNOTATION_ONLY_RESPONSE.data = {
  'annotations': ['cat', 'dog']
}

const EXPRESSION_ONLY_RESPONSE = _cloneDeep(ANNOTATION_ONLY_RESPONSE)
EXPRESSION_ONLY_RESPONSE.data = {
  'expression': [0.25, 2.3]
}
EXPRESSION_ONLY_RESPONSE.genes = ['Apoe']

const CLUSTER_AND_EXPRESSION_RESPONSE = _cloneDeep(FETCH_CLUSTER_RESPONSE)
CLUSTER_AND_EXPRESSION_RESPONSE.data.expression = [0.25, 2.3]
CLUSTER_AND_EXPRESSION_RESPONSE.genes = ['Apoe']

afterEach(() => {
  jest.clearAllMocks()
})

describe('Plot data cache', () => {
  it('caches a single cluster call for use when annotation and gene are changed', async () => {
    const cache = createCache()
    const apiFetch = jest.spyOn(ScpApi, 'fetchCluster')
    // pass in a clone of the response since it may get modified by the cache operations
    apiFetch.mockImplementation(() => Promise.resolve([_cloneDeep(FETCH_CLUSTER_RESPONSE), 230]))

    // first, check that the repsonse is fetched and returned normally if not in cache
    const response = await cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: '_default',
      annotation: {},
      subsample: ''
    })
    const expectedApiParams = {
      annotation: {},
      cluster: '_default',
      consensus: undefined,
      fields: ['coordinates', 'cells', 'annotation'],
      genes: [],
      isAnnotatedScatter: null,
      isCorrelatedScatter: null,
      studyAccession: 'SCP1',
      subsample: ''
    }
    expect(apiFetch).toHaveBeenLastCalledWith(expectedApiParams)
    expect(response).toEqual([FETCH_CLUSTER_RESPONSE, 230])

    // second, check that it only fetches the needed fields when changing annotation
    apiFetch.mockImplementation(() => Promise.resolve([_cloneDeep(ANNOTATION_ONLY_RESPONSE), 230]))
    const annotResponse = await cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: 'cluster.tsv',
      annotation: {
        name: 'species',
        scope: 'study'
      },
      subsample: 'all'
    })
    const expectedNewAnnotParams = {
      annotation: { name: 'species', scope: 'study' },
      cluster: 'cluster.tsv',
      consensus: undefined,
      fields: ['annotation'],
      genes: [],
      isAnnotatedScatter: null,
      isCorrelatedScatter: null,
      studyAccession: 'SCP1',
      subsample: 'all'
    }
    expect(apiFetch).toHaveBeenLastCalledWith(expectedNewAnnotParams)


    // confirm the fields got merged
    const scatterData = annotResponse[0].data
    expect(scatterData.x).toEqual(FETCH_CLUSTER_RESPONSE.data.x)
    expect(scatterData.y).toEqual(FETCH_CLUSTER_RESPONSE.data.y)
    expect(scatterData.cells).toEqual(FETCH_CLUSTER_RESPONSE.data.cells)
    expect(scatterData.annotations).toEqual(ANNOTATION_ONLY_RESPONSE.data.annotations)
    expect(annotResponse[0].annotParams.name).toEqual('species')


    // third, check that the cache works if a gene is then searched
    apiFetch.mockImplementation(() => Promise.resolve([_cloneDeep(EXPRESSION_ONLY_RESPONSE), 230]))
    const geneResponse = await cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: 'cluster.tsv',
      annotation: {
        name: 'species',
        scope: 'study'
      },
      genes: ['Apoe'],
      subsample: 'all'
    })
    const expectedNewGeneParams = {
      annotation: { name: 'species', scope: 'study' },
      cluster: 'cluster.tsv',
      consensus: undefined,
      fields: ['expression'],
      genes: ['Apoe'],
      isAnnotatedScatter: null,
      isCorrelatedScatter: null,
      studyAccession: 'SCP1',
      subsample: 'all'
    }
    expect(apiFetch).toHaveBeenLastCalledWith(expectedNewGeneParams)

    // confirm the fields got merged
    const geneScatterData = geneResponse[0].data
    expect(geneScatterData.x).toEqual(FETCH_CLUSTER_RESPONSE.data.x)
    expect(geneScatterData.y).toEqual(FETCH_CLUSTER_RESPONSE.data.y)
    expect(geneScatterData.cells).toEqual(FETCH_CLUSTER_RESPONSE.data.cells)
    expect(geneScatterData.annotations).toEqual(ANNOTATION_ONLY_RESPONSE.data.annotations)
    expect(geneScatterData.expression).toEqual(EXPRESSION_ONLY_RESPONSE.data.expression)
    expect(geneResponse[0].annotParams.name).toEqual('species')
  })

  // same test as above, but  for a case where the user changes the annotation before the original cluster call returns
  it('does not double-fetch cluster data, even when the cluster data has not yet been received', async () => {
    const cache = createCache()
    const apiFetch = jest.spyOn(ScpApi, 'fetchCluster')
    // pass in a clone of the response since it may get modified by the cache operations
    apiFetch.mockImplementation(() => Promise.resolve([_cloneDeep(FETCH_CLUSTER_RESPONSE), 230]))
    // don't use await here, since we need to execute another fetch before this one completes
    cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: '_default',
      annotation: {},
      subsample: 'all'
    })

    apiFetch.mockImplementation(() => Promise.resolve([_cloneDeep(ANNOTATION_ONLY_RESPONSE), 230]))
    const newAnnotResponse = await cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: '_default',
      annotation: {
        name: 'species',
        scope: 'study'
      },
      subsample: 'all'
    })

    // it should still only fetch the annotation data, even though the cluster data has not yet arrived
    const expectedNewAnnotParams = {
      annotation: { name: 'species', scope: 'study' },
      cluster: '_default',
      consensus: undefined,
      fields: ['annotation'],
      genes: [],
      isAnnotatedScatter: null,
      isCorrelatedScatter: null,
      studyAccession: 'SCP1',
      subsample: 'all'
    }

    expect(apiFetch).toHaveBeenLastCalledWith(expectedNewAnnotParams)


    // check the merge was successful
    const scatterData = newAnnotResponse[0].data
    expect(scatterData.x).toEqual(FETCH_CLUSTER_RESPONSE.data.x)
    expect(scatterData.y).toEqual(FETCH_CLUSTER_RESPONSE.data.y)
    expect(scatterData.cells).toEqual(FETCH_CLUSTER_RESPONSE.data.cells)
    expect(scatterData.annotations).toEqual(ANNOTATION_ONLY_RESPONSE.data.annotations)
    expect(newAnnotResponse[0].annotParams.name).toEqual('species')
  })
})

describe('cache handles simultaneous gene/cluster plots', () => {
  // this test corresponds to the case where a user lands directly on the explore gene search page
  // either from a link, or by reloading the page while a gene search is displayed
  it('does not fetch any data for cluster if expression plot is made first', async () => {
    const cache = createCache()
    const apiFetch = jest.spyOn(ScpApi, 'fetchCluster')
    apiFetch.mockImplementation(() => Promise.resolve([_cloneDeep(CLUSTER_AND_EXPRESSION_RESPONSE), 230]))

    // do a request for the full gene plot, don't await since we want to send the cluster request before this finishes
    const expressionFetchResult = cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: '_default',
      genes: ['Apoe'],
      annotation: {
        name: 'species',
        scope: 'study'
      },
      subsample: 'all'
    })
    const expectedApiParams = {
      annotation: {
        name: 'species',
        scope: 'study'
      },
      cluster: '_default',
      consensus: undefined,
      fields: ['coordinates', 'cells', 'annotation', 'expression'],
      genes: ['Apoe'],
      isAnnotatedScatter: null,
      isCorrelatedScatter: null,
      studyAccession: 'SCP1',
      subsample: 'all'
    }
    expect(apiFetch).toHaveBeenLastCalledWith(expectedApiParams)
    // do a request for the cluster plot
    const clusterFetchResult = cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: '_default',
      annotation: {
        name: 'species',
        scope: 'study'
      },
      subsample: 'all'
    })
    // make sure no new request is sent to the server
    expect(apiFetch).toHaveBeenCalledTimes(1)

    const expressionResponse = await expressionFetchResult
    expect(expressionResponse).toEqual([CLUSTER_AND_EXPRESSION_RESPONSE, 230])
    const clusterResponse = await clusterFetchResult

    expect(clusterResponse[0].data).toEqual(FETCH_CLUSTER_RESPONSE.data)
    expect(clusterResponse[0].annotParams).toEqual(FETCH_CLUSTER_RESPONSE.annotParams)

    // // now simulate a user changing annotation
    // const mockApiResponse = _cloneDeep(ANNOTATION_ONLY_RESPONSE)
    // mockApiResponse.genes = ['Apoe']
    // apiFetch.mockImplementation(() => Promise.resolve([mockApiResponse, 230]))
    // const expressionFetchResult2 = cache.fetchCluster({
    //   studyAccession: 'SCP1',
    //   cluster: 'cluster.tsv',
    //   genes: ['Apoe'],
    //   subsample: 'all',
    //   consensus: null,
    //   annotation: {
    //     name: 'species',
    //     scope: 'study'
    //   }
    // })
    // const expectedApiParams2 = {
    //   annotation: {
    //     name: 'species',
    //     scope: 'study'
    //   },
    //   cluster: 'cluster.tsv',
    //   consensus: null,
    //   fields: ['annotation'],
    //   genes: ['Apoe'],
    //   isAnnotatedScatter: null,
    //   isCorrelatedScatter: null,
    //   studyAccession: 'SCP1',
    //   subsample: 'all'
    // }
    // expect(apiFetch).toHaveBeenLastCalledWith(expectedApiParams2)

    // const clusterFetchResult2 = cache.fetchCluster({
    //   'studyAccession': 'SCP1',
    //   'cluster': 'cluster.tsv',
    //   'consensus': null,
    //   'annotation': {
    //     name: 'species',
    //     scope: 'study'
    //   },
    //   'subsample': 'all'
    // })
    // // changing annotation should only result in a single call, even with two plots displayed,
    // // so the total number of calls should now be 2
    // expect(apiFetch).toHaveBeenCalledTimes(2)

    // const expResponse2 = await expressionFetchResult2
    // const expectedAnnotResponse = _cloneDeep(CLUSTER_AND_EXPRESSION_RESPONSE)
    // expectedAnnotResponse.annotParams = ANNOTATION_ONLY_RESPONSE.annotParams
    // expectedAnnotResponse.data.annotations = ANNOTATION_ONLY_RESPONSE.data.annotations
    // expect(expResponse2).toEqual([expectedAnnotResponse, 230])

    // const clusterResponse2 = await clusterFetchResult2
    // const scatterData = clusterResponse2[0].data
    // expect(scatterData.x).toEqual(FETCH_CLUSTER_RESPONSE.data.x)
    // expect(scatterData.y).toEqual(FETCH_CLUSTER_RESPONSE.data.y)
    // expect(scatterData.cells).toEqual(FETCH_CLUSTER_RESPONSE.data.cells)
    // expect(scatterData.annotations).toEqual(ANNOTATION_ONLY_RESPONSE.data.annotations)
  })

  it('does not attempt to cache subsampled data', async () => {
    const cache = createCache()
    const apiFetch = jest.spyOn(ScpApi, 'fetchCluster')
    // pass in a clone of the response since it may get modified by the cache operations
    apiFetch.mockImplementation(() => Promise.resolve([_cloneDeep(FETCH_CLUSTER_RESPONSE), 230]))

    // first, check that the repsonse is fetched and returned normally on first load
    const response = await cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: '_default',
      subsample: '1000',
      annotation: {}
    })
    const expectedApiParams = {
      annotation: {},
      cluster: '_default',
      consensus: undefined,
      fields: ['coordinates', 'cells', 'annotation'],
      genes: [],
      isAnnotatedScatter: null,
      isCorrelatedScatter: null,
      studyAccession: 'SCP1',
      subsample: '1000'
    }

    expect(apiFetch).toHaveBeenLastCalledWith(expectedApiParams)
    expect(response).toEqual([FETCH_CLUSTER_RESPONSE, 230])

    // second, check that it refetches everything
    cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: '_default',
      annotation: {
        name: 'species',
        scope: 'study'
      },
      subsample: '1000'
    })
    const expectedNewAnnotParams = {
      annotation: { name: 'species', scope: 'study' },
      cluster: '_default',
      consensus: undefined,
      fields: ['coordinates', 'cells', 'annotation'],
      genes: [],
      isAnnotatedScatter: null,
      isCorrelatedScatter: null,
      studyAccession: 'SCP1',
      subsample: '1000'
    }
    expect(apiFetch).toHaveBeenLastCalledWith(expectedNewAnnotParams)
  })

  it('does not attempt to cache user annotations', async () => {
    const cache = createCache()
    const apiFetch = jest.spyOn(ScpApi, 'fetchCluster')
    // pass in a clone of the response since it may get modified by the cache operations
    apiFetch.mockImplementation(() => Promise.resolve([{
      ..._cloneDeep(FETCH_CLUSTER_RESPONSE),
      annotParams: {
        name: 'userStuff',
        type: 'group',
        scope: 'user',
        values: ['foo', 'bar'],
        identifier: 'userStuff--group--user'
      }
    }, 230]))

    await cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: 'cluster.tsv',
      subsample: 'all',
      annotation: {
        name: 'userStuff',
        scope: 'user'
      }
    })

    // check that it refetches the annotation if an expression graph is then queried
    cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: 'cluster.tsv',
      subsample: 'all',
      annotation: {
        name: 'userStuff',
        scope: 'user'
      },
      genes: ['agpat2']
    })
    const expectedNewAnnotParams = {
      annotation: { name: 'userStuff', scope: 'user' },
      cluster: 'cluster.tsv',
      consensus: undefined,
      fields: ['annotation', 'expression'],
      genes: ['agpat2'],
      isAnnotatedScatter: null,
      isCorrelatedScatter: null,
      studyAccession: 'SCP1',
      subsample: 'all'
    }
    expect(apiFetch).toHaveBeenLastCalledWith(expectedNewAnnotParams)
  })

  it('handles caching after a cluster change', async () => {
    const cache = createCache()
    const apiFetch = jest.spyOn(ScpApi, 'fetchCluster')
    // pass in a clone of the response since it may get modified by the cache operations
    apiFetch.mockImplementation(() => Promise.resolve([_cloneDeep(FETCH_CLUSTER_RESPONSE), 230]))

    // check that the repsonse is fetched and returned normally if not in cache
    await cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: '_default',
      annotation: {},
      subsample: ''
    })

    // check that it refetches everything after a cluster change
    apiFetch.mockImplementation(() => Promise.resolve([{
      ..._cloneDeep(FETCH_CLUSTER_RESPONSE),
      cluster: 'cluster2.tsv'
    }, 230]))
    await cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: 'cluster2.tsv',
      annotation: {
        name: 'biosample_id',
        scope: 'study'
      },
      subsample: 'all'
    })
    const expectedNewClusterParams = {
      annotation: { name: 'biosample_id', scope: 'study' },
      cluster: 'cluster2.tsv',
      consensus: undefined,
      fields: ['coordinates', 'cells', 'annotation'],
      genes: [],
      isAnnotatedScatter: null,
      isCorrelatedScatter: null,
      studyAccession: 'SCP1',
      subsample: 'all'
    }
    expect(apiFetch).toHaveBeenLastCalledWith(expectedNewClusterParams)

    // second, check that it only fetches the needed fields when changing annotation
    apiFetch.mockImplementation(() => Promise.resolve([{
      ..._cloneDeep(ANNOTATION_ONLY_RESPONSE),
      cluster: 'cluster2.tsv'
    }, 230]))
    const annotResponse = await cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: 'cluster2.tsv',
      annotation: {
        name: 'species',
        scope: 'study'
      },
      subsample: 'all'
    })
    const expectedNewAnnotParams = {
      annotation: { name: 'species', scope: 'study' },
      cluster: 'cluster2.tsv',
      consensus: undefined,
      fields: ['annotation'],
      genes: [],
      isAnnotatedScatter: null,
      isCorrelatedScatter: null,
      studyAccession: 'SCP1',
      subsample: 'all'
    }
    expect(apiFetch).toHaveBeenLastCalledWith(expectedNewAnnotParams)


    // confirm the fields got merged
    const scatterData = annotResponse[0].data
    expect(scatterData.x).toEqual(FETCH_CLUSTER_RESPONSE.data.x)
    expect(scatterData.y).toEqual(FETCH_CLUSTER_RESPONSE.data.y)
    expect(scatterData.cells).toEqual(FETCH_CLUSTER_RESPONSE.data.cells)
    expect(scatterData.annotations).toEqual(ANNOTATION_ONLY_RESPONSE.data.annotations)
    expect(annotResponse[0].annotParams.name).toEqual('species')


    // check that the cache works if a gene is then searched
    apiFetch.mockImplementation(() => Promise.resolve([{
      ..._cloneDeep(EXPRESSION_ONLY_RESPONSE),
      cluster: 'cluster2.tsv'
    }, 230]))
    const geneResponse = await cache.fetchCluster({
      studyAccession: 'SCP1',
      cluster: 'cluster2.tsv',
      annotation: {
        name: 'species',
        scope: 'study'
      },
      genes: ['Apoe'],
      subsample: 'all'
    })
    const expectedNewGeneParams = {
      annotation: { name: 'species', scope: 'study' },
      cluster: 'cluster2.tsv',
      consensus: undefined,
      fields: ['expression'],
      genes: ['Apoe'],
      isAnnotatedScatter: null,
      isCorrelatedScatter: null,
      studyAccession: 'SCP1',
      subsample: 'all'
    }
    expect(apiFetch).toHaveBeenLastCalledWith(expectedNewGeneParams)

    // confirm the fields got merged
    const geneScatterData = geneResponse[0].data
    expect(geneScatterData.x).toEqual(FETCH_CLUSTER_RESPONSE.data.x)
    expect(geneScatterData.y).toEqual(FETCH_CLUSTER_RESPONSE.data.y)
    expect(geneScatterData.cells).toEqual(FETCH_CLUSTER_RESPONSE.data.cells)
    expect(geneScatterData.annotations).toEqual(ANNOTATION_ONLY_RESPONSE.data.annotations)
    expect(geneScatterData.expression).toEqual(EXPRESSION_ONLY_RESPONSE.data.expression)
    expect(geneResponse[0].annotParams.name).toEqual('species')
  })
})

