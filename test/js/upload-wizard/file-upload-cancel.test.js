import React from 'react'
import { render, screen, waitForElementToBeRemoved, fireEvent } from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'
import _cloneDeep from 'lodash/cloneDeep'
import { ReactNotifications } from 'react-notifications-component'

import { RawUploadWizard } from 'components/upload/UploadWizard'
import MockRouter from '../lib/MockRouter'
import { fireFileSelectionEvent } from '../lib/file-mock-utils'
import * as ScpApi from 'lib/scp-api'
import { EMPTY_STUDY, GENERIC_EXPLORE_INFO} from './file-info-responses'

describe('cancels a study file upload', () => {
  afterEach(() => {
    // Restores all mocks back to their original value
    jest.restoreAllMocks()
  })

  it('shows the cancel button for in-progress uploads', async () => {
    const studyInfoSpy = jest.spyOn(ScpApi, 'fetchStudyFileInfo')
    // pass in a clone of the response since it may get modified by the cache operations
    studyInfoSpy.mockImplementation(params => {
      const response = _cloneDeep(EMPTY_STUDY)
      return Promise.resolve(response)
    })
    const exploreSpy = jest.spyOn(ScpApi, 'fetchExplore')
    exploreSpy.mockImplementation(params => {
      const response = _cloneDeep(GENERIC_EXPLORE_INFO)
      return Promise.resolve(response)
    })

    const createFileSpy = jest.spyOn(ScpApi, 'createStudyFile')
    // create promise that will not resolve
    createFileSpy.mockImplementation(() => new Promise(() => {}))
    const deleteFileSpy = jest.spyOn(ScpApi, 'deleteStudyFile')
    deleteFileSpy.mockImplementation(() => new Promise(() => {}))
    render(<>
      <ReactNotifications/>
      <MockRouter>
        <RawUploadWizard studyAccession="SCP1" name="Chicken study"/>
      </MockRouter>
    </>)
    const saveButton = () => screen.getByTestId('file-save')
    await waitForElementToBeRemoved(() => screen.getByTestId('upload-wizard-spinner'))
    fireEvent.click(screen.getByText('Miscellaneous'))
    const fileName = 'miscText.txt'
    fireFileSelectionEvent(screen.getByTestId('file-input'), {
      fileName,
      content: 'Stuff and things\n'
    })
    await waitForElementToBeRemoved(() => screen.getByTestId('file-validation-spinner'))
    expect(screen.getByTestId('file-selection-name')).toHaveTextContent(fileName)
    expect(saveButton()).not.toBeDisabled()

    expect(screen.queryByTestId('upload-cancel-btn')).toBeNull()
    fireEvent.click(saveButton())
    expect(screen.getByTestId('upload-cancel-btn')).toBeInTheDocument()
    fireEvent.click(screen.getByTestId('upload-cancel-btn'))

    fireEvent.click(screen.getByTestId('upload-cancel-yes-btn'))

    // should delete the file from the form and call the delete method
    expect(screen.getByTestId('file-input-btn')).toHaveTextContent('Choose file')
    expect(screen.queryByTestId('file-selection-name')).toBeNull()
    expect(deleteFileSpy).toHaveBeenCalledTimes(0)
    // the delete is only called after a delay
    await new Promise(r => setTimeout(r, 600))
    expect(deleteFileSpy).toHaveBeenCalledTimes(1)
  })
})
