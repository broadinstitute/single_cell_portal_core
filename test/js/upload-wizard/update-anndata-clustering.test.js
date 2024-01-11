import { screen, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import { renderWizardWithStudyOnClusteringStep } from './upload-wizard-test-utils'
import { ANNDATA_FILE_STUDY } from './file-info-responses'
import fetch from 'node-fetch'
import { setMetricsApiMockFlag } from 'lib/metrics-api'
import { getTokenExpiry } from './upload-wizard-test-utils'

describe('it allows clustering updates on AnnData file', () => {
  beforeAll(() => {
    global.fetch = fetch
    setMetricsApiMockFlag(true)
    window.SCP = {
      readOnlyTokenObject: {
        'access_token': 'test',
        'expires_in': 3600, // 1 hour in seconds
        'expires_at': getTokenExpiry()
      },
      readOnlyToken: 'test'
    }
  })
  afterEach(() => {
    // Restores all mocks back to their original value
    jest.restoreAllMocks()
  })

  it('navigates to AnnData clustering step and expect an "add clustering" button to be available', async () => {
    await renderWizardWithStudyOnClusteringStep({
      featureFlags: { ingest_anndata_file: true }, studyInfo: ANNDATA_FILE_STUDY
    })

    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Expression matrices')
    fireEvent.click(screen.getByText('Clustering'))
    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Clustering')
    expect(screen.getByTestId('add-file-button')).toHaveTextContent('Add clustering')
  })

  it('navigates to AnnData clustering step and expect no delete button available', async () => {
    await renderWizardWithStudyOnClusteringStep({
      featureFlags: { ingest_anndata_file: true }, studyInfo: ANNDATA_FILE_STUDY
    })

    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Expression matrices')
    fireEvent.click(screen.getByText('Clustering'))

    // the test file has only one clustering so cannot delete it
    expect(screen.queryByTestId('file-delete')).toBeNull()
  })
})

// TODO (SCP-5126)
// change a clustering name
// delete a clustering
