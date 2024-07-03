// Without disabling eslint code, Promises are auto inserted
/* eslint-disable*/

import React from 'react'
import { render, waitForElementToBeRemoved, screen } from '@testing-library/react'
import { enableFetchMocks } from 'jest-fetch-mock'
import Plotly from 'plotly.js-dist'
import jquery from 'jquery'

import ScatterPlot from 'components/visualization/ScatterPlot'

jest.mock('lib/scp-api-metrics', () => ({
  logScatterPlot: jest.fn()
}))

const fs = require('fs')

enableFetchMocks()

const mockStudyPath = 'public/mock_data/search/annotated_scatter_plot/study_human_all_genes.json'
const study = JSON.parse(fs.readFileSync(mockStudyPath), 'utf8')

const mockAnnotatedScatterPath =
  'public/mock_data/search/annotated_scatter_plot/adcy5_human_all_genes.json'
const plots = fs.readFileSync(mockAnnotatedScatterPath)

beforeAll(() => {
  global.$ = jquery
})
// Note: tests that mock global.fetch must be cleared after every test
afterEach(() => {
  // Restores all mocks back to their original value
  jest.restoreAllMocks()
})

describe('Annotated scatter plot in global gene search', () => {
  beforeEach(() => {
    fetch.resetMocks()
  })

  it('configures Plotly annotated scatter', async() => {
    fetch.mockResponseOnce(plots)
    const mockPlot = jest.spyOn(Plotly, 'react')
    mockPlot.mockImplementation(() => {})

    render(
      <ScatterPlot
        studyAccession={study.accession}
        genes={study.gene_matches}
        cluster=''
        annotation={{name: 'Intensity', type: 'numeric', scope: 'cluster'}}
        isAnnotatedScatter={study.is_default_annotation_numeric}
      />
    )

    await waitForElementToBeRemoved(() => screen.getByTestId('study-scatter-1-loading-icon'))

    var args = mockPlot.mock.calls[0];

    expect(args[0]).toBe('study-scatter-1')

    const firstTrace = args[1][0]
    expect(firstTrace.type).toBe('scattergl')
    expect(firstTrace.y).toHaveLength(2)

    expect(args[2].yaxis.title).toBe('Expression')

  })

})
