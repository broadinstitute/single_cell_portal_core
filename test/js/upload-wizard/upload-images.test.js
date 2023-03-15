import { screen, fireEvent, waitForElementToBeRemoved } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'

import { IMAGE_FILE } from './file-info-responses'
import { fireFileSelectionEvent } from '../lib/file-mock-utils'
import { renderWizardWithStudy, saveButton, mockCreateStudyFile } from './upload-wizard-test-utils'

describe('Upload wizard supports reference images', () => {
  it('validates bad file names, starts upload of JPEG file', async () => {
    const createFileSpy = mockCreateStudyFile(IMAGE_FILE)

    await renderWizardWithStudy({ featureFlags: { reference_image_upload: true, ingest_anndata_file: false } })

    const formData = new FormData()
    fireEvent.click(screen.getByText('Reference images'))

    expect(screen.getByRole('heading', { level: 4 })).toHaveTextContent('Reference images')

    expect(saveButton()).toBeDisabled()
    fireEvent.mouseOver(saveButton())
    expect(screen.getByRole('tooltip')).toHaveTextContent('You must select a file')

    const badFileName = 'raw_counts.wrong'
    fireFileSelectionEvent(screen.getByTestId('file-input'), {
      fileName: badFileName,
      content: 'crap\n'
    })
    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
    expect(screen.getByTestId('validation-error')).toHaveTextContent(`after correcting ${badFileName}`)

    const imageFileName = 'chicken.jpeg'
    fireFileSelectionEvent(screen.getByTestId('file-input'), {
      fileName: imageFileName,
      content: 'binarystuff' // we'll want to update this if we ever add client-side image file format checks
    })
    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))

    expect(screen.getByTestId('file-selection-name')).toHaveTextContent(imageFileName)
    expect(saveButton()).not.toBeDisabled()

    fireEvent.click(saveButton())
    await waitForElementToBeRemoved(() => screen.getByTestId('file-save-spinner'))

    expect(createFileSpy).toHaveBeenLastCalledWith(expect.objectContaining({
      chunkEnd: 11,
      chunkStart: 0,
      fileSize: 11,
      isChunked: false,
      studyAccession: 'SCP1',
      studyFileData: formData
    }))
    expect(screen.getByTestId('images-status-badge')).toHaveClass('complete')
  })
})
