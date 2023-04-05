/** React component for displaying the file upload wizard
 *
 * All the state for both the user's changes, and the state of the study as known from the server are
 * managed here as formState, and serverState, respectively.  This component owns many state-manipulation
 * methods, like updateFile.  Any update to any file will trigger a re-render of the entire upload widget.
 */

import React, { useState, useEffect } from 'react'

import _cloneDeep from 'lodash/cloneDeep'
import _isMatch from 'lodash/isMatch'
import { ReactNotifications, Store } from 'react-notifications-component'
import { Router, useLocation, navigate } from '@reach/router'
import * as queryString from 'query-string'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faChevronLeft, faChevronRight } from '@fortawesome/free-solid-svg-icons'

import { formatFileFromServer, formatFileForApi, newStudyFileObj, StudyContext } from './upload-utils'
import {
  createStudyFile, updateStudyFile, deleteStudyFile,
  fetchStudyFileInfo, sendStudyFileChunk, RequestCanceller
} from '~/lib/scp-api'
import MessageModal, { successNotification, failureNotification } from '~/lib/MessageModal'
import UserProvider from '~/providers/UserProvider'
import ErrorBoundary from '~/lib/ErrorBoundary'

import WizardNavPanel from './WizardNavPanel'
import ClusteringStep from './ClusteringStep'
import SpatialStep from './SpatialStep'
import ImageStep from './ImageStep'
import CoordinateLabelStep from './CoordinateLabelStep'
import RawCountsStep from './RawCountsStep'
import ProcessedExpressionStep from './ProcessedExpressionStep'
import MetadataStep from './MetadataStep'
import MiscellaneousStep from './MiscellaneousStep'
import SequenceFileStep from './SequenceFileStep'
import GeneListStep from './GeneListStep'
import LoadingSpinner from '~/lib/LoadingSpinner'
import AnnDataStep, { AnnDataFileFilter } from './AnnDataStep'
import AnnDataUploadStep from './AnnDataUploadStep'
import SeuratStep from './SeuratStep'
import UploadExperienceSplitter from './UploadExperienceSplitter'
import AnnDataExpressionStep from './AnnDataExpressionStep'


const POLLING_INTERVAL = 10 * 1000 // 10 seconds between state updates
const CHUNK_SIZE = 10000000 // 10 MB

const ALL_POSSIBLE_STEPS = [
  RawCountsStep,
  ProcessedExpressionStep,
  MetadataStep,
  ClusteringStep,
  AnnDataUploadStep,
  SpatialStep,
  CoordinateLabelStep,
  SequenceFileStep,
  GeneListStep,
  MiscellaneousStep,
  SeuratStep,
  AnnDataStep,
  ImageStep
]

// These steps remain the same for both classic and AnnData upload experiences
const MAIN_STEPS_CLASSIC = [
  RawCountsStep,
  ProcessedExpressionStep,
  MetadataStep,
  ClusteringStep
]

const MAIN_STEPS_ANNDATA = [
  AnnDataExpressionStep,
  MetadataStep,
  ClusteringStep,
  AnnDataUploadStep
]

/** shows the upload wizard */
export function RawUploadWizard({ studyAccession, name }) {
  const [serverState, setServerState] = useState(null)
  const [formState, setFormState] = useState(null)

  // study attributes to pass to the StudyContext later for use throughout the RawUploadWizard component, if needed
  // use complete study object, rather than defaultStudyState so that any updates to study.rb will be reflected in
  // this context
  const studyObj = serverState?.study


  // used for toggling between the split view for the upload experiences
  const [choiceMade, setChoiceMade] = useState(false)
  const allowReferenceImageUpload = serverState?.feature_flags?.reference_image_upload
  // used for toggling between classic and AnnData experience of upload wizard
  const [isAnnDataExperience, setIsAnnDataExperience] = useState(
    formState?.files?.filter(AnnDataFileFilter)?.length > 0 &&
    serverState?.feature_flags?.ingest_anndata_file
  )

  let MAIN_STEPS
  let SUPPLEMENTAL_STEPS
  let NON_VISUALIZABLE_STEPS

  // set the additional steps to display, based on classic or AnnData experience
  if (isAnnDataExperience) {
    MAIN_STEPS = MAIN_STEPS_ANNDATA
    SUPPLEMENTAL_STEPS = ALL_POSSIBLE_STEPS.slice(6, 7)
    NON_VISUALIZABLE_STEPS = ALL_POSSIBLE_STEPS.slice(8, 10)
  } else {
    MAIN_STEPS = MAIN_STEPS_CLASSIC
    SUPPLEMENTAL_STEPS = ALL_POSSIBLE_STEPS.slice(5, 9)
    NON_VISUALIZABLE_STEPS = ALL_POSSIBLE_STEPS.slice(9, 12)
    if (allowReferenceImageUpload) {
      SUPPLEMENTAL_STEPS.splice(1, 0, ImageStep)
    }
  }
  const STEPS = MAIN_STEPS.concat(SUPPLEMENTAL_STEPS, NON_VISUALIZABLE_STEPS)

  const routerLocation = useLocation()
  const queryParams = queryString.parse(routerLocation.search)

  let currentStepIndex = STEPS.findIndex(step => step.name === queryParams.tab)
  if (currentStepIndex < 0) {
    currentStepIndex = 0
  }
  const currentStep = STEPS[currentStepIndex]

  // go through the files and compute any relevant derived properties, notably 'isDirty'
  if (formState?.files) {
    formState.files.forEach(file => {
      const serverFile = serverState.files ? serverState.files.find(sFile => sFile._id === file._id) : null
      file.serverFile = serverFile

      // use isMatch to confirm that specified properties are equal, but ignore properties (like isDirty)
      // that only exist on the form state objects
      if (!_isMatch(file, serverFile) || file.status === 'new') {
        file.isDirty = true
      }
    })
  }

  /** move the wizard to the given step tab */
  function setCurrentStep(newStep) {
    // for steps in the upload process
    if (newStep.name) {
      navigate(`?tab=${newStep.name}`)
      window.scrollTo(0, 0)
    }
    // for the upload data split view
    else {
      navigate(newStep)
    }
  }

  /** adds an empty file, merging in the given fileProps. Does not communicate anything to the server
   * By default, will scroll the window to show the new file
   * */
  function addNewFile(fileProps, scrollToBottom = false) {
    const newFile = newStudyFileObj(serverState.study._id.$oid)
    Object.assign(newFile, fileProps)

    setFormState(prevFormState => {
      const newState = _cloneDeep(prevFormState)
      newState.files.push(newFile)
      return newState
    })
    if (scrollToBottom) {
      window.setTimeout(() => scroll({ top: document.body.scrollHeight, behavior: 'smooth' }), 100)
    }
  }

  /** handle response from server after an upload by updating the serverState with the updated file response */
  function handleSaveResponse(response, uploadingMoreChunks, requestCanceller) {
    const updatedFile = formatFileFromServer(response)
    const fileId = updatedFile._id
    if (requestCanceller.wasCancelled) {
      Store.addNotification(failureNotification(`${updatedFile.name} save cancelled`))
      updateFile(fileId, { isSaving: false, requestCanceller: null })
      return
    }

    // first update the serverState
    setServerState(prevServerState => {
      const newServerState = _cloneDeep(prevServerState)
      let fileIndex = newServerState.files.findIndex(f => f._id === fileId)
      if (fileIndex < 0) {
        // this is a new file -- add it to the end of the list
        fileIndex = newServerState.files.length
      }
      newServerState.files[fileIndex] = updatedFile
      return newServerState
    })
    // then update the form state
    setFormState(prevFormState => {
      const newFormState = _cloneDeep(prevFormState)
      const fileIndex = newFormState.files.findIndex(f => f._id === fileId)
      const formFile = _cloneDeep(updatedFile)
      if (uploadingMoreChunks) {
        // copy over the previous files saving states
        const oldFormFile = newFormState.files[fileIndex]
        formFile.isSaving = true
        formFile.saveProgress = oldFormFile.saveProgress
        formFile.cancelUpload = oldFormFile.cancelUpload
      }

      newFormState.files[fileIndex] = formFile
      return newFormState
    })
    if (!uploadingMoreChunks) {
      Store.addNotification(successNotification(`${updatedFile.name} saved successfully`))
    }
  }

  /** Updates file fields by merging in the 'updates', does not perform any validation, and
   *  does not save to the server */
  function updateFile(fileId, updates) {
    setFormState(prevFormState => {
      const newFormState = _cloneDeep(prevFormState)
      let fileChanged = newFormState.files.find(f => f._id === fileId)
      if (!fileChanged && isAnnDataExperience) {
        const annDataFile = newFormState.files.find(f => f.file_type === 'AnnData')
        const fragments = annDataFile?.ann_data_file_info?.data_fragments || []
        fileChanged = fragments.find(f => f._id === fileId)
      } if (!fileChanged) { // we're updating a stale/no-longer existent file -- discard it
        return prevFormState
      }
      ['heatmap_file_info', 'expression_file_info'].forEach(nestedProp => {
        if (updates[nestedProp]) {
          // merge nested file info properties
          Object.assign(fileChanged[nestedProp], updates[nestedProp])
          delete updates[nestedProp]
        }
      })
      Object.assign(fileChanged, updates)
      return newFormState
    })
  }

  /** handler for progress events from an XMLHttpRequest call.
   *    Updates the overall save progress of the file
   */
  function handleSaveProgress(progressEvent, fileId, fileSize, chunkStart) {
    if (!fileSize) {
      return // this is just a field update with no upload, so no need to show progress
    }
    // the progress event sometimes reports more than the actual size sent
    // maybe because of some minimum buffer size?
    const amountSent = Math.min(CHUNK_SIZE, progressEvent.loaded)
    let overallCompletePercent = (chunkStart + amountSent) / fileSize * 100
    // max at 98, since the progress event comes based on what's sent.
    // we always still will need to wait for the server to respond after we get to 100
    overallCompletePercent = Math.round(Math.min(overallCompletePercent, 98))
    updateFile(fileId, { saveProgress: overallCompletePercent })
  }

  /** cancels the pending upload and deletes the file */
  async function cancelUpload(requestCanceller) {
    requestCanceller.cancel()
    const fileId = requestCanceller.fileId

    deleteFileFromForm(fileId)
    // wait a brief amount of time to minimize the timing edge case where the user hits 'cancel' while the request
    // completed.  In that case the file will have been saved, but we won't have the new id yet.  We need to wait until
    // the id comes back so we can address the delete request properly
    // We also don't await the delete since if it errors, it is likely because the file never got created or
    // got deleted for other reasons (e.g. invalid form data) in the meantime
    setTimeout(() => deleteFileFromServer(requestCanceller.fileId), 500)
  }

  /** save the given file and perform an upload if a selected file is present */
  async function saveFile(file) {
    let studyFileId = file._id

    if (isAnnDataExperience) {
      // enable ingest of data by setting reference_anndata_file = false
      file['reference_anndata_file'] = false
      formState.files.forEach(fileFormData => {
        if (fileFormData.file_type === 'Cluster') {
          fileFormData.data_type = 'cluster'

          // mulitple clustering forms are allowed so add each as a fragment to the AnnData file
          const annDataFile = formState.files.find(f => f.file_type === 'AnnData')
          annDataFile?.ann_data_file_info ? '': annDataFile['ann_data_file_info'] = {}
          const fragments = annDataFile.ann_data_file_info?.data_fragments || []
          fragments.push(fileFormData)

          annDataFile.ann_data_file_info.data_fragments = fragments
        }
        if (fileFormData.file_type === 'Expression Matrix') {
          file['extra_expression_form_info'] = fileFormData
        }
        if (fileFormData.file_type === 'Metadata') {
          file['metadata_form_info'] = fileFormData
        }
      })
    }

    const fileSize = file.uploadSelection?.size
    const isChunked = fileSize > CHUNK_SIZE
    let chunkStart = 0
    let chunkEnd = Math.min(CHUNK_SIZE, fileSize)

    const studyFileData = formatFileForApi(file, chunkStart, chunkEnd)
    try {
      let response
      const requestCanceller = new RequestCanceller(studyFileId)
      if (fileSize) {
        updateFile(studyFileId, { isSaving: true, cancelUpload: () => cancelUpload(requestCanceller) })
      } else {
        // if there isn't an associated file upload, don't allow the user to cancel the request
        updateFile(studyFileId, { isSaving: true })
      }

      if (file.status === 'new') {
        response = await createStudyFile({
          studyAccession, studyFileData, isChunked, chunkStart, chunkEnd, fileSize, requestCanceller,
          onProgress: e => handleSaveProgress(e, studyFileId, fileSize, chunkStart)
        })
      } else {
        response = await updateStudyFile({
          studyAccession, studyFileId, studyFileData, isChunked, chunkStart, chunkEnd, fileSize, requestCanceller,
          onProgress: e => handleSaveProgress(e, studyFileId, fileSize, chunkStart)
        })
      }
      handleSaveResponse(response, isChunked, requestCanceller)
      // copy over the new id from the server
      studyFileId = response._id
      requestCanceller.fileId = studyFileId
      if (isChunked && !requestCanceller.wasCancelled) {
        while (chunkEnd < fileSize && !requestCanceller.wasCancelled) {
          chunkStart += CHUNK_SIZE
          chunkEnd = Math.min(chunkEnd + CHUNK_SIZE, fileSize)
          const chunkApiData = formatFileForApi(file, chunkStart, chunkEnd)
          response = await sendStudyFileChunk({
            studyAccession, studyFileId, studyFileData: chunkApiData, chunkStart, chunkEnd, fileSize, requestCanceller,
            onProgress: e => handleSaveProgress(e, studyFileId, fileSize, chunkStart)
          })
        }
        handleSaveResponse(response, false, requestCanceller)
      }
    } catch (error) {
      Store.addNotification(failureNotification(<span>{file.name} failed to save<br />{error}</span>))
      updateFile(studyFileId, {
        isSaving: false
      })
    }
  }

  /** delete the file from the form, and also the server if it exists there */
  async function deleteFile(file) {
    const fileId = file._id
    if (file.status === 'new' || file?.serverFile?.parse_status === 'failed') {
      deleteFileFromForm(fileId)
    } else {
      updateFile(fileId, { isDeleting: true })
      try {
        await deleteFileFromServer(fileId)
        deleteFileFromForm(fileId)
        Store.addNotification(successNotification(`${file.name} deleted successfully`))
      } catch (error) {
        Store.addNotification(failureNotification(<span>{file.name} failed to delete<br />{error.message}</span>))
        updateFile(fileId, {
          isDeleting: false
        })
      }
    }
  }

  /** removes a file from the form only, does not touch server data */
  function deleteFileFromForm(fileId) {
    setFormState(prevFormState => {
      const newFormState = _cloneDeep(prevFormState)
      newFormState.files = newFormState.files.filter(f => f._id != fileId)
      return newFormState
    })
  }

  /** deletes the file from the server */
  async function deleteFileFromServer(fileId) {
    await deleteStudyFile(studyAccession, fileId)
    setServerState(prevServerState => {
      const newServerState = _cloneDeep(prevServerState)
      newServerState.files = newServerState.files.filter(f => f._id !== fileId)
      return newServerState
    })
  }

  /** poll the server periodically for updates to files */
  function pollServerState() {
    fetchStudyFileInfo(studyAccession, false).then(response => {
      response.files.forEach(file => formatFileFromServer(file))
      setServerState(oldState => {
        // copy over the menu options since they aren't included in the polling response
        response.menu_options = oldState.menu_options
        return response
      })

      setTimeout(pollServerState, POLLING_INTERVAL)
    }).catch(response => {
      // if the get fails, it's very likely that the error recur on a retry
      // (user's session timed out, server downtime, internet connection issues)
      // so to avoid repeated error messages, show one error, and stop polling
      Store.addNotification(failureNotification(<span>
        Server connectivity failed--some functions may not be available.<br />
        You may want to reload the page or sign in again.
      </span>))
    })
  }

  // on initial load, load all the details of the study and study files
  useEffect(() => {
    fetchStudyFileInfo(studyAccession).then(response => {
      response.files.forEach(file => formatFileFromServer(file))
      setIsAnnDataExperience(
        response.files?.filter(AnnDataFileFilter)?.length > 0 &&
        response.feature_flags?.ingest_anndata_file)
      setServerState(response)
      setFormState(_cloneDeep(response))
      setTimeout(pollServerState, POLLING_INTERVAL)
    })

    window.document.title = `Upload - Single Cell Portal`
  }, [studyAccession])

  const nextStep = STEPS[currentStepIndex + 1]
  const prevStep = STEPS[currentStepIndex - 1]

  /**
   * Returns the appropriate content to display for the UploadWizard
   * @returns The content for the upload wizard, either the steps for upload or the split view for choosing the data upload experience
   */
  function getWizardContent(formState, serverState) {
    if (!formState?.files.length && !choiceMade && serverState?.feature_flags?.ingest_anndata_file) {
      return <UploadExperienceSplitter {...{ setIsAnnDataExperience, setChoiceMade }} />
    } else if (choiceMade || formState?.files.length || !serverState?.feature_flags?.ingest_anndata_file) {
      return <> <div className="row wizard-content">
        <div>
          <WizardNavPanel {...{
            formState, serverState, currentStep, setCurrentStep, studyAccession, mainSteps: MAIN_STEPS,
            supplementalSteps: SUPPLEMENTAL_STEPS, nonVizSteps: NON_VISUALIZABLE_STEPS, studyName: name, isAnnDataExperience
          }} />
        </div>
        <div id="overflow-x-scroll">
          <div className="flexbox-align-center top-margin margin-left">
            <h4>{currentStep.header}</h4>
            <div className="prev-next-buttons">
              {prevStep && <button
                className="btn terra-tertiary-btn margin-right"
                onClick={() => setCurrentStep(prevStep)}>
                <FontAwesomeIcon icon={faChevronLeft} /> Previous
              </button>}
              {nextStep && <button
                className="btn terra-tertiary-btn"
                onClick={() => setCurrentStep(nextStep)}>
                Next <FontAwesomeIcon icon={faChevronRight} />
              </button>}
            </div>
          </div>
          <div>
            <currentStep.component
              setCurrentStep={setCurrentStep}
              formState={formState}
              serverState={serverState}
              deleteFile={deleteFile}
              updateFile={updateFile}
              saveFile={saveFile}
              addNewFile={addNewFile}
              isAnnDataExperience={isAnnDataExperience}
              deleteFileFromForm={deleteFileFromForm}
            />
          </div>
        </div>
      </div></>
    }
  }

  /** return a button for switching to the other experience (AnnData or Classic) */
  function getOtherChoiceButton() {
    const otherOption = isAnnDataExperience ? 'classic upload' : 'AnnData upload'
    return <button
      data-testid="switch-upload-mode-button"
      className="btn terra-secondary-btn margin-left-extra"
      onClick={() => setIsAnnDataExperience(!isAnnDataExperience)}> Switch to {otherOption}
    </button>
  }

  return (
    <StudyContext.Provider value={studyObj}>
      {/* If the formState hasn't loaded show a spinner */}
      {(!formState && !serverState) && <div>
        <LoadingSpinner className="spinner-full-page" testId="upload-wizard-spinner" /> </div>
      }
      {!!formState &&
        <div className="upload-wizard-react">
          <div className="row">
            <div className="col-md-12 wizard-top-bar no-wrap-ellipsis">
              <a href={`/single_cell/study/${studyAccession}`}>View study</a> / &nbsp;
              <span title="{serverState?.study?.name}">{serverState?.study?.name}</span>
              {/* only allow switching modes if the user hasn't uploaded a file yet */}
              {!serverState?.files.length && choiceMade && serverState?.feature_flags?.ingest_anndata_file && getOtherChoiceButton()}
            </div>
            {getWizardContent(formState, serverState)}
          </div>
          <MessageModal />
        </div>}
    </StudyContext.Provider>
  )
}

/** Wraps the upload wizard logic in a router and error handler */
export default function UploadWizard({ studyAccession, name }) {
  return <ErrorBoundary>
    <UserProvider>
      <ReactNotifications />
      <Router>
        <RawUploadWizard studyAccession={studyAccession} name={name} default />
      </Router>
    </UserProvider>
  </ErrorBoundary>
}
