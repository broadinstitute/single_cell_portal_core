import React from 'react'
import { render, screen, waitForElementToBeRemoved } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'
import * as Reach from '@reach/router'
import jquery from 'jquery'

import MockRouter from '../lib/MockRouter'
import * as ScpApi from 'lib/scp-api'
import ExploreView from 'components/explore/ExploreView'
import { mockPerformance } from '../mock-performance'

beforeAll(() => {
  global.$ = jquery
  mockPerformance('')
  global.morpheus = { HeatMap: function Heatmap() {} }
})
// Note: tests that mock global.fetch must be cleared after every test
afterEach(() => {
  // Restores all mocks back to their original value
  jest.restoreAllMocks()
})


describe('correctly routes to precomputed heatmap if no clusters present', () => {
  it('renders by default if no clusters', async () => {
    const routerNav = jest.spyOn(Reach, 'navigate')
    const exploreSpy = jest.spyOn(ScpApi, 'fetchExplore')
    exploreSpy.mockImplementation(() => ({
      'inferCNVIdeogramFiles': null,
      'bamBundleList': [],
      'uniqueGenes': [
        'ADCY5',
        'AGPAT2'
      ],
      'geneLists': [
        {
          'name': 'time_varying_genes',
          'heatmap_file_info': {
            '_id': {
              '$oid': '626892f3cc7ba073111aae92'
            },
            'custom_scaling': true,
            'color_min': -1,
            'color_max': 0.6,
            'legend_label': 'diffExp4'
          },
          'description': 'genes varying over time (SCP4 staging)'
        }
      ],
      'precomputedHeatmapLabel': 'custom diff. expression',
      'annotationList': {
        'default_cluster': null,
        'default_annotation': null,
        'annotations': [],
        'clusters': [],
        'subsample_thresholds': {}
      },
      'clusterGroupNames': [],
      'spatialGroups': [],
      'imageFiles': [],
      'taxonNames': [],
      'genes': [],
      'clusterPointAlpha': 1,
      'colorProfile': null,
      'bucketId': 'fc-6e8a0a4d-6493-401c-b47c-1025a583f237'
    }))

    render(<MockRouter><ExploreView studyAccession='SCP101'/></MockRouter>)
    await waitForElementToBeRemoved(() => screen.getByTestId('explore-spinner'))
    // should set the geneList and the heatmapFit to 'both'
    expect(routerNav).toHaveBeenLastCalledWith('?geneList=time_varying_genes&heatmapFit=both', { replace: true })
    // the heatmap tab should have the description displayed
    expect(screen.getByText('genes varying over time (SCP4 staging)')).toBeInTheDocument()
  })
})
