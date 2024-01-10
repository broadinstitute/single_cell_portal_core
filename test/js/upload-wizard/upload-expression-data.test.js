const fetch = require('node-fetch')
import { screen, fireEvent, waitForElementToBeRemoved } from '@testing-library/react'
import { setMetricsApiMockFlag } from 'lib/metrics-api'
import '@testing-library/jest-dom/extend-expect'
import selectEvent from 'react-select-event'

import {
  RAW_COUNTS_MTX_FILE, BARCODES_FILE, FEATURES_FILE, EMPTY_STUDY
} from './file-info-responses'

import { fireFileSelectionEvent } from '../lib/file-mock-utils'

import { renderWizardWithStudy, getSelectByLabelText, mockCreateStudyFile } from './upload-wizard-test-utils'

describe('it allows uploading of expression matrices', () => {
  beforeAll(() => {
    jest.restoreAllMocks()
    jest.setTimeout(10000)
    global.fetch = fetch
    setMetricsApiMockFlag(true)
    window.SCP = {
      readOnlyToken: 'test'
    }
  })

  it('uploads a raw counts mtx file', async () => {
    const createFileSpy = mockCreateStudyFile(RAW_COUNTS_MTX_FILE)
    const { container } = await renderWizardWithStudy({})

    const formData = new FormData()

    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Raw count expression files')
    fireEvent.click(screen.getByLabelText('Sparse matrix (.mtx)'))

    // get the features and barcodes file forms
    let subForms = container.querySelectorAll('.sub-form')
    expect(subForms).toHaveLength(2)
    expect(subForms[0].querySelector('h5')).toHaveTextContent('10x Features File')
    expect(subForms[1].querySelector('h5')).toHaveTextContent('10x Barcodes File')

    const badFileName = 'raw_counts.wrong'
    fireFileSelectionEvent(screen.getAllByTestId('file-input')[0], {
      fileName: badFileName,
      content: '%%MatrixMarket matrix coordinate integer general\n8 10 2\n1 1 1\n1 7 2\n'
    })
    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
    expect(screen.getByTestId('validation-error')).toHaveTextContent(`after correcting ${badFileName}`)

    const mtxFileName = 'raw_counts.mtx'
    fireFileSelectionEvent(screen.getAllByTestId('file-input')[0], {
      fileName: mtxFileName,
      content: '%%MatrixMarket matrix coordinate integer general\n8 10 2\n1 1 1\n1 7 2\n'
    })
    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
    expect(screen.getByTestId('rawCounts-status-badge')).toHaveTextContent('1')
    expect(screen.getByTestId('file-selection-name')).toHaveTextContent(mtxFileName)
    const mainSaveButton = () => screen.getAllByTestId('file-save')[0]
    expect(mainSaveButton()).toBeDisabled()

    fireEvent.mouseOver(mainSaveButton())
    expect(screen.getByRole('tooltip')).toHaveTextContent('You must specify: units')
    expect(screen.getByRole('tooltip')).toHaveTextContent('You must specify: species')
    expect(screen.getByRole('tooltip')).toHaveTextContent('You must specify: Library preparation protocol')

    await selectEvent.select(getSelectByLabelText(screen, 'Species *'), 'chicken')
    await selectEvent.select(getSelectByLabelText(screen, 'Library preparation protocol *'), 'Drop-seq')
    await selectEvent.select(getSelectByLabelText(screen, 'Units *'), 'raw counts')
    expect(mainSaveButton()).not.toBeDisabled()

    fireEvent.mouseOver(subForms[1].querySelector('button[data-testid="file-save"]'))
    expect(screen.getByRole('tooltip')).toHaveTextContent('Parent file must be saved first')

    fireEvent.click(mainSaveButton())
    await waitForElementToBeRemoved(() => screen.getByTestId('file-save-spinner'))

    expect(createFileSpy).toHaveBeenLastCalledWith(expect.objectContaining({
      chunkEnd: 68,
      chunkStart: 0,
      fileSize: 68,
      isChunked: false,
      studyAccession: 'SCP1',
      studyFileData: formData
    }))

    // Now check that we can upload the barcodes and features files
    // start with barcodes
    subForms = container.querySelectorAll('.sub-form')
    mockCreateStudyFile(BARCODES_FILE, createFileSpy)

    fireEvent.mouseOver(subForms[1].querySelector('button[data-testid="file-save"]'))
    expect(screen.getByRole('tooltip')).not.toHaveTextContent('Parent file must be saved first')
    expect(screen.getByRole('tooltip')).toHaveTextContent('You must select a file to upload or specify a remote file')

    fireFileSelectionEvent(subForms[1].querySelector('input[data-testid="file-input"]'), {
      fileName: 'barcodes.txt',
      content: 'cell1\ncell2\ncell3\ncell4\ncell5\ncell6\ncell7\ncell8\n'
    })

    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
    expect(subForms[1].querySelector('button[data-testid="file-save"]')).not.toBeDisabled()
    fireEvent.click(subForms[1].querySelector('button[data-testid="file-save"]'))
    await waitForElementToBeRemoved(() => screen.getByTestId('file-save-spinner'))

    // now upload the features file
    subForms = container.querySelectorAll('.sub-form')
    mockCreateStudyFile(FEATURES_FILE, createFileSpy)

    fireEvent.mouseOver(subForms[0].querySelector('button[data-testid="file-save"]'))
    expect(screen.getByRole('tooltip')).toHaveTextContent('You must select a file to upload or specify a remote file')

    fireFileSelectionEvent(subForms[0].querySelector('input[data-testid="file-input"]'), {
      fileName: 'features.txt',
      content: 'cell1,cell2,cell3,cell4,cell5,cell6,cell7,cell8\n'
    })

    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
    fireEvent.click(subForms[0].querySelector('button[data-testid="file-save"]'))
    await waitForElementToBeRemoved(() => screen.getByTestId('file-save-spinner'))

    // confirm all the filenames and headers are correct
    const headerList = screen.getAllByRole('heading', { level: 5 }).map(h => h.textContent)
    expect(headerList).toEqual([
      'raw_counts.mtx',
      '10x Features File',
      'features.txt',
      '10x Barcodes File',
      'barcodes.txt'
    ])
  })

  it('correctly displays a previously uploaded mtx file bundle', async () => {
    // When files are uploaded via the new or legacy wizard, their bundle parent is indicated
    // via the study file options hash.  However, for some sync studies, the parent will only
    // be indicated via the bundle.  So check that we handle that case appropriately
    const bundleId = '6191fb48771a5b0d8b5a0a98'
    const studyInfo = {
      ...EMPTY_STUDY,
      files: [
        {
          ...RAW_COUNTS_MTX_FILE,
          options: {},
          study_file_bundle_id: { $oid: bundleId }
        },
        {
          ...FEATURES_FILE,
          options: {},
          study_file_bundle_id: { $oid: bundleId }
        },
        {
          ...BARCODES_FILE,
          options: {},
          study_file_bundle_id: { $oid: bundleId }
        }
      ]
    }
    await renderWizardWithStudy({ studyInfo })
    // confirm all the filenames and headers are correct
    const headerList = screen.getAllByRole('heading', { level: 5 }).map(h => h.textContent)
    expect(headerList).toEqual([
      'raw_counts.mtx',
      '10x Features File',
      'features.txt',
      '10x Barcodes File',
      'barcodes.txt'
    ])
  })
})
