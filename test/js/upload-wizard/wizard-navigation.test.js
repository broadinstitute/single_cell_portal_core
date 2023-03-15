import { screen, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import { renderWizardWithStudy } from './upload-wizard-test-utils'
import * as ScpApi from 'lib/scp-api'


describe('it allows navigating between steps', () => {
  afterEach(() => {
    // Restores all mocks back to their original value
    jest.restoreAllMocks()
  })

  it('navigates between steps on clicking step names', async () => {
    await renderWizardWithStudy({ featureFlags: { ingest_anndata_file: false } })

    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Raw count expression files')

    fireEvent.click(screen.getByText('Processed matrices'))
    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Processed expression files')

    fireEvent.click(screen.getByText('Coordinate labels'))
    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Coordinate labels')
  })

  it('prevents access to processed matrices when appropriate', async () => {
    await renderWizardWithStudy({ featureFlags: { raw_counts_required_frontend: true, ingest_anndata_file: false } })

    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Raw count expression files')
    expect(screen.queryByTestId('file-upload-overlay')).not.toBeInTheDocument()
    fireEvent.click(screen.getByText('Processed matrices'))
    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Processed expression files')
    expect(screen.queryByTestId('processed-matrix-overlay')).toBeInTheDocument()
  })

  it('sets initial tab based on url params', async () => {
    jest.spyOn(ScpApi, 'fetchStudyFileInfo').mockImplementation(() => {return new Promise(() => {})})
    await renderWizardWithStudy(
      {
        featureFlags: { raw_counts_required_frontend: true, ingest_anndata_file: false },
        initialSearch: '?tab=clustering',
        studyAccession: 'SCP1',
        studyName: 'Chicken study'
      }
    )

    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Clustering')
  })
})
