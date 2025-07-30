import React from 'react'
import { render, screen, fireEvent, act } from '@testing-library/react'
import * as ScpApi from 'lib/scp-api'
import '@testing-library/jest-dom/extend-expect'

import ResultsExport from 'components/search/results/ResultsExport'

describe('Results Export Test', () => {
  const emptyResults = { results: { studies: [] } }
  const hasResults = { results: { studies: [ { name: 'Test result' }] } }

  it('renders when results are present', () => {
    render(<ResultsExport studySearchState={hasResults} />)
    const exportButton = screen.getByTestId('export-search-results-tsv')
    expect(exportButton).toBeInTheDocument()
    expect(exportButton).not.toBeDisabled()
  })

  it('disables button when no results', () => {
    render(<ResultsExport studySearchState={emptyResults} />)
    const exportButton = screen.getByTestId('export-search-results-tsv')
    expect(exportButton).toBeInTheDocument()
    expect(exportButton).toBeDisabled()
  })

  it('disables button when exporting', async () => {
    jest.spyOn(ScpApi, 'exportSearchResultsText').mockImplementation(params => {
      const response = "Exported data"
      return Promise.resolve(response)
    })
    act(async () => {
      render(<ResultsExport studySearchState={hasResults} />)
      const exportButton = screen.getByTestId('export-search-results-tsv')
      fireEvent.click(exportButton)
    })
    const exportingText = screen.getByText('Exporting...')
    expect(exportingText).toBeInTheDocument()
  })
})
