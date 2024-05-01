// Without disabling eslint code, Promises are auto inserted
/* eslint-disable*/

import React from 'react'
import { render, waitForElementToBeRemoved, screen } from '@testing-library/react'
import { enableFetchMocks } from 'jest-fetch-mock'

import * as WebWorker from 'lib/web-worker'
import StudyViolinPlot, {filterResults} from 'components/visualization/StudyViolinPlot'
import Plotly from 'plotly.js-dist'
import * as UserProvider from '~/providers/UserProvider'

jest.mock('lib/scp-api-metrics', () => ({
  logViolinPlot: jest.fn()
}))

const fs = require('fs')

enableFetchMocks()

const mockStudyPath = 'public/mock_data/search/violin_plot/study_small_intestinal_epithelium.json'
const study = JSON.parse(fs.readFileSync(mockStudyPath), 'utf8')

const mockViolinsPath =
  'public/mock_data/search/violin_plot/expression_violin_mrpl15_small_intestinal_epithelium.json'
const violins = fs.readFileSync(mockViolinsPath)

const mockClusterAllPath =
  'public/mock_data/search/violin_plot/cluster_all_small_intestinal_epithelium.json'
const clusterAll = fs.readFileSync(mockClusterAllPath)

describe('Violin plot in global gene search', () => {
  beforeEach(() => {
    fetch.resetMocks()
  })

  it('configures Plotly violin plot', async() => {
    fetch.mockResponseOnce(violins)
    fetch.mockResponseOnce(clusterAll)
    const mockPlot = jest.spyOn(Plotly, 'newPlot')
    mockPlot.mockImplementation(() => {})

    const gene = study.gene_matches[0]

    const mockInitViolinWorker = jest.spyOn(WebWorker, 'initViolinWorker')
    mockInitViolinWorker.mockImplementation(() => {
      global.SCP.violinCellIndexes = {}
    })
    const mockWorkSetViolinCellIndexes = jest.spyOn(WebWorker, 'workSetViolinCellIndexes')
    mockWorkSetViolinCellIndexes.mockImplementation(() => {
      global.SCP.violinCellIndexes[gene] = [1,2,3,4]
    })

    render(<StudyViolinPlot studyAccession={study.accession}
      genes={study.gene_matches}
      cluster=''
      annotation={{name: '', type: '', scope: ''}}
    />)

    await waitForElementToBeRemoved(() => screen.getByTestId('study-violin-1-loading-icon'))

    var args = mockPlot.mock.calls[0];

    expect(args[0]).toBe('study-violin-1')

    const firstTrace = args[1][0]
    expect(firstTrace.type).toBe('violin')
    expect(firstTrace.name).toBe('Enterocyte.Immature.Distal')
    expect(firstTrace.y).toHaveLength(512)

    expect(args[2].xaxis.type).toBe('category')

  })

  it('skips index for cell filtering when disabled via flag', async () => {
    // This confirms cell filtering can be disabled to unblock violin plots
    // in very large studies.

    jest
      .spyOn(UserProvider, 'getFeatureFlagsWithDefaults')
      .mockReturnValue({
        show_cell_facet_filtering: false
      })

    const results = [1, 2, 3]

    const filteredResults = await filterResults(
      'SCP123', {}, {}, 'NF2', results, {}, []
    )

    expect(filteredResults).toEqual(results)
  })

})
