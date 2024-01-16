// Without disabling eslint code, Promises are auto inserted
/* eslint-disable*/

import React from 'react'
import { render, waitForElementToBeRemoved, screen } from '@testing-library/react'
import { enableFetchMocks } from 'jest-fetch-mock'

import StudyViolinPlot from 'components/visualization/StudyViolinPlot'
import Plotly from 'plotly.js-dist'

jest.mock('lib/scp-api-metrics', () => ({
  logViolinPlot: jest.fn()
}))

const fs = require('fs')

enableFetchMocks()

global.URL.revokeObjectURL = jest.fn()

const mockStudyPath = 'public/mock_data/search/violin_plot/study_small_intestinal_epithelium.json'
const study = JSON.parse(fs.readFileSync(mockStudyPath), 'utf8')

const mockViolinsPath =
  'public/mock_data/search/violin_plot/expression_violin_mrpl15_small_intestinal_epithelium.json'
const violins = fs.readFileSync(mockViolinsPath)

describe('Violin plot in global gene search', () => {
  beforeEach(() => {
    fetch.resetMocks()
  })

  it('configures Plotly violin plot', async() => {
    fetch.mockResponseOnce(violins)
    const mockPlot = jest.spyOn(Plotly, 'newPlot')
    mockPlot.mockImplementation(() => {})

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

})
