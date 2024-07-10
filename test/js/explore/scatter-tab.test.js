import React from 'react'
import _cloneDeep from 'lodash/cloneDeep'
import jquery from 'jquery'
import { render, screen } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'
import Plotly from 'plotly.js-dist'

import * as ScpApi from 'lib/scp-api'
import { createCache } from 'components/explore/plot-data-cache'
import ScatterTab, { getNewContextMap } from 'components/explore/ScatterTab'
import * as ScpApiMetrics from 'lib/scp-api-metrics'
import * as LayoutUtils from 'lib/layout-utils'


// models a real response from api/v1/visualization/clusters
const MOCK_CLUSTER_RESPONSE = {
  data: {
    annotations: ['foo', 'bar'],
    cells: ['A', 'B'],
    expression: [1, 2],
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
  consensus: null,
  externalLink: { url: '', title: '', description: '' },
  customColors: {}
}

const CACHE_PERF_PARAMS = {
  legacyBackend: 0,
  parse: 0,
  url: 'cache'
}

const MOCK_EXPLORE_RESPONSE = {
  annotationList: {
    default_cluster: 'clusterA',
    annotations: [],
    clusters: [],
    default_annotation: {},
    subsample_thresholds: {}
  },
  bamBundleList: [],
  cluster: { numPoints: 40, isSubsampled: false },
  clusterGroupNames: ['clusterA'],
  clusterPointAlpha: 1,
  colorProfile: null,
  geneLists: [],
  inferCNVIdeogramFiles: null,
  spatialGroups: [],
  taxonNames: ['Gallus gallus'],
  uniqueGenes: ['Foo', 'Bar'],
  imageFiles: []
}

beforeAll(() => {
  global.$ = jquery
})
// Note: tests that mock global.fetch must be cleared after every test
afterEach(() => {
  // Restores all mocks back to their original value
  jest.restoreAllMocks()
})


describe('getNewContextMap correctly assigns contexts', () => {
  it('assigns correctly on first pass', async () => {
    const scatterParams = [{
      cluster: 'clusterA',
      annotation: { name: 'annotA' },
      genes: ['gene1']
    }, {
      cluster: 'clusterA',
      annotation: { name: 'annotA' },
      genes: []
    }]
    const newMap = getNewContextMap(scatterParams, {})
    expect(newMap).toEqual({
      'clusterAgene1annotA': 'A',
      'clusterAannotA': 'B'
    })
  })

  it('preserves the cluster context when adding a gene expression plot', async () => {
    const scatterParams = [{
      cluster: 'clusterA',
      annotation: { name: 'annotA' },
      genes: ['gene1']
    }, {
      cluster: 'clusterA',
      annotation: { name: 'annotA' },
      genes: []
    }]
    const newMap = getNewContextMap(scatterParams, { 'clusterAannotA': 'A' })
    expect(newMap).toEqual({
      'clusterAgene1annotA': 'B',
      'clusterAannotA': 'A'
    })
  })

  it('preserves the cluster context when removing a gene expression plot', async () => {
    const scatterParams = [{
      cluster: 'clusterA',
      annotation: { name: 'annotA' },
      genes: []
    }]
    const newMap = getNewContextMap(scatterParams, {
      'clusterAgene1annotA': 'A',
      'clusterAannotA': 'B'
    })
    expect(newMap).toEqual({
      'clusterAannotA': 'B'
    })
  })

  it('generates scatter plots and titles for spatial clusters', async () => {
    const apiFetch = jest.spyOn(ScpApi, 'fetchCluster')
    // pass in a clone of the response since it may get modified by the cache operations
    apiFetch.mockImplementation(params => {
      const response = _cloneDeep(MOCK_CLUSTER_RESPONSE)
      response.cluster = params.cluster
      response.genes = params.genes
      return Promise.resolve([response, CACHE_PERF_PARAMS])
    })
    const fakePlot = jest.spyOn(Plotly, 'react')
    fakePlot.mockImplementation(() => {})
    const fakeLogScatter = jest.spyOn(ScpApiMetrics, 'logScatterPlot')
    fakeLogScatter.mockImplementation(() => {})

    const getTextSizeSpy = jest.spyOn(LayoutUtils, 'getTextSize')
    getTextSizeSpy.mockImplementation(() => {
      return [10, 10]
    })

    render((
      <ScatterTab
        studyAccession='SCP101'
        exploreParamsWithDefaults={{
          cluster: 'clusterA',
          spatialGroups: ['spatialClusterA'],
          annotation: { name: 'biosample_id', type: 'group', scope: 'study' },
          genes: ['farsa']
        }}
        updateExploreParamsWithDefaults={() => {}}
        exploreInfo={MOCK_EXPLORE_RESPONSE}
        isGene={true}
        isMultiGene={false}
        getPlotDimensions={() => [10, 10]}
        dataCache={createCache()}
        setCountsByLabel={function() {}}
        countsByLabel={[]}
      />
    ))

    await screen.findByTestId('study-scatter-1')
    const plotTitles = screen.getAllByRole('heading')

    expect(plotTitles).toHaveLength(4)
    const expectedTitles = [
      'farsa expression clusterA',
      'clusterA',
      'farsa expression spatialClusterA',
      'spatialClusterA'
    ]
    plotTitles.forEach((titleEl, index) => {
      expect(titleEl).toHaveTextContent(expectedTitles[index])
    })
  })
})
