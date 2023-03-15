import React from 'react'
import { render, screen, waitForElementToBeRemoved } from '@testing-library/react'
import _cloneDeep from 'lodash/cloneDeep'
import { ReactNotifications } from 'react-notifications-component'

import MockRouter from '../lib/MockRouter'
import { UserContext } from 'providers/UserProvider'
import { RawUploadWizard } from 'components/upload/UploadWizard'
import * as ScpApi from 'lib/scp-api'
import { EMPTY_STUDY } from './file-info-responses'

/** gets a pointer to the react-select node based on label text
 * This is non-trivial since our labels contain the select,
 * and so a naive getByLabelText will not work.
 * Instead we get the label using getByText and assume
 * the first div inside is the react-select element */
export function getSelectByLabelText(screen, text) {
  return screen.getByText(text).querySelector('div')
}

/** renders the upload wizard with the given studyInfo response, and waits for the loading
 * spinner to clear
*/
export async function renderWizardWithStudy({
  studyInfo=EMPTY_STUDY, featureFlags={}, studyAccession='SCP1', studyName='Chickens', initialSearch={}
}) {
  // merge featureFlags data into studyInfo.feature_flags since this is where the upload wizard looks now
  studyInfo.feature_flags = featureFlags

  const studyInfoSpy = jest.spyOn(ScpApi, 'fetchStudyFileInfo')
  // pass in a clone of the response since it may get modified by the cache operations
  studyInfoSpy.mockImplementation(params => {
    const response = _cloneDeep(studyInfo)
    return Promise.resolve(response)
  })

  const renderResult = render(
    <UserContext.Provider value={{ featureFlagsWithDefaults: featureFlags }}>
      <ReactNotifications/>
      <MockRouter initialSearch={initialSearch}>
        <RawUploadWizard studyAccession={studyAccession} name={studyName}/>
      </MockRouter>
    </UserContext.Provider>)
  await waitForElementToBeRemoved(() => screen.getByTestId('upload-wizard-spinner'))

  return renderResult
}

/** mocks the create file API call to return the given file, but with an id that matches what was actually saved
*/
export function mockCreateStudyFile(returnFileObj, createFileSpy) {
  if (!createFileSpy) {
    createFileSpy = jest.spyOn(ScpApi, 'createStudyFile')
  }
  // do a deep clone to be safe against subsequent object updates
  const returnFile = _cloneDeep(returnFileObj)
  createFileSpy.mockImplementation(saveFile => {
    // read the generated ID from the FormData, so we can return it and it will be matched in the UX
    // do the same for other id-related fields
    const idToAssign = saveFile.studyFileData.get('study_file[_id]')
    returnFile._id = { $oid: idToAssign }
    if (saveFile.studyFileData.get('study_file[options][matrix_id]')) {
      returnFile.options = { matrix_id: saveFile.studyFileData.get('study_file[options][matrix_id]') }
    }
    if (saveFile.studyFileData.get('study_file[expression_file_info_attributes][raw_counts_associations][]')) {
      returnFile.expression_file_info.raw_counts_associations = saveFile.studyFileData.getAll('study_file[expression_file_info_attributes][raw_counts_associations][]')
    }
    return returnFile
  })
  return createFileSpy
}

/** gets the current save button */
export function saveButton() {
  return screen.getByTestId('file-save')
}
