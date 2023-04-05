import { screen, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import { renderWizardWithStudy } from './upload-wizard-test-utils'
import * as ScpApi from 'lib/scp-api'
import { ANNDATA_FILE_STUDY, METADATA_AND_EXPRESSION_FILE_STUDY } from './file-info-responses'


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

  it('navigates to classic steps when study already has classic files uploaded', async () => {
    await renderWizardWithStudy({ featureFlags: { ingest_anndata_file: true }, studyInfo: METADATA_AND_EXPRESSION_FILE_STUDY })

    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Raw count expression files')
  })

  it('navigates to AnnData steps when study already has AnnData file uploaded', async () => {
    await renderWizardWithStudy({ featureFlags: { ingest_anndata_file: true }, studyInfo: ANNDATA_FILE_STUDY })

    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Expression matrices')
  })

  it('shows split options page when the study is empty navigate to Classic mode', async () => {
    await renderWizardWithStudy({ featureFlags: { ingest_anndata_file: true } })

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Introducing AnnData file upload to power visualizations')

    fireEvent.click(screen.getByText('Classic'))
    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Raw count expression files')

  })

  it('shows split options page when the study is empty navigate to AnnData mode', async () => {
    await renderWizardWithStudy({ featureFlags: { ingest_anndata_file: true } })

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Introducing AnnData file upload to power visualizations')

    fireEvent.click(screen.getByText('AnnData'))
    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Expression matrices')

  })

  it('allows toggling of modes as appropriate', async () => {
    await renderWizardWithStudy({ featureFlags: { ingest_anndata_file: true } })

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Introducing AnnData file upload to power visualizations')

    fireEvent.click(screen.getByText('AnnData'))
    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Expression matrices')

    fireEvent.click(screen.getByTestId('switch-upload-mode-button'))
    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Raw count expression files')

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
