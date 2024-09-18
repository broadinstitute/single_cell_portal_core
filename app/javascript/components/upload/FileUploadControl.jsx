import React, { useState, useContext } from 'react'

import { bytesToSize } from '~/lib/stats'
import FileDownloadControl from '~/components/download/FileDownloadControl'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { StudyContext } from '~/components/upload/upload-utils'
import ValidateFile from '~/lib/validation/validate-file'
import ValidationMessage from '~/components/validation/ValidationMessage'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faExternalLinkSquareAlt } from '@fortawesome/free-solid-svg-icons'
import { Popover, OverlayTrigger } from 'react-bootstrap'

// File types which let the user set a custom name for the file in the UX
const FILE_TYPES_ALLOWING_SET_NAME = ['Cluster', 'Gene List']


/** renders a file upload control for the given file object */
export default function FileUploadControl({
  file, allFiles, updateFile,
  allowedFileExts=['*'],
  validationIssues={},
  bucketName, isAnnDataExperience
}) {
  const [fileValidation, setFileValidation] = useState({
    validating: false, issues: {}, fileName: null
  })
  const inputId = `file-input-${file._id}`
  const [showUploadButton, setShowUploadButton] = useState(true)
  const [showBucketPath, setShowBucketPath] = useState(false)
  const ToggleUploadButton = () => {
    // this is an inverted check since the user is clicking and the value is about to change
    if (!showUploadButton) {
      unsetRemoteLocation()
    }
    setShowUploadButton(!showUploadButton)
    setShowBucketPath(!showBucketPath)
  }
  const study = useContext(StudyContext)

  const toggleText = showUploadButton ? 'Use bucket path' : 'Upload local file'
  const toggleTooltip = showBucketPath ?
    'Upload a file from your computer' :
    "Input a path to a file that is already in this study's bucket"
  const uploadToggle = <span
    className='btn btn-default margin-left'
    onClick={ToggleUploadButton}
    data-toggle="tooltip"
    data-original-title={toggleTooltip}>{toggleText}
  </span>

  const bucketPopover = <Popover id={`bucket-upload-help-${file._id}`}>
    <a href='https://singlecell.zendesk.com/hc/en-us/articles/360061006011' target='_blank'>
      Learn how to upload large files
    </a>
  </Popover>
  const googleBucketLink =
    <OverlayTrigger trigger={['hover', 'focus']} rootClose placement="top" overlay={bucketPopover} delayHide={1500}>
      <a className='btn btn-default margin-left'
         href={`https://accounts.google.com/AccountChooser?continue=https://console.cloud.google.com/storage/browser/${bucketName}`}
         target='_blank'><FontAwesomeIcon icon={faExternalLinkSquareAlt} /> Browse bucket</a>
    </OverlayTrigger>

  /** handle user interaction with the file input */
  async function handleFileSelection(e) {
    const selectedFile = e.target.files[0]

    let newName = selectedFile.name

    // for cluster and other named files, don't change an existing customized name
    if (FILE_TYPES_ALLOWING_SET_NAME.includes(file.file_type) && file.name && file.name !== file.upload_file_name) {
      newName = file.name
    }

    setFileValidation({ validating: true, issues: {}, fileName: selectedFile.name })
    const [issues, notes] = await ValidateFile.validateLocalFile(selectedFile, file, allFiles, allowedFileExts)
    setFileValidation({ validating: false, issues, fileName: selectedFile.name, notes })
    if (issues.errors.length === 0) {
      updateFile(file._id, {
        uploadSelection: selectedFile,
        upload_file_name: selectedFile.name,
        name: newName,
        notes
      })
    }
  }

  // keep track of pending timeout for remote validation via bucket path
  const [timeOutId, setTimeOutID] = useState(null)

  // clear out remote_location and hasRemoteFile to allow switching back to file upload button
  function unsetRemoteLocation() {
    updateFile(file._id, {remote_location: '', hasRemoteFile: false})
  }

  // perform CSFV on remote file when specifying a GS URL or bucket path
  // will sanitize GS URL before calling validateRemoteFile
  async function handleBucketLocationEntry(path) {
    const matcher = new RegExp(`(gs:\/\/)?${bucketName}\/?`)
    const trimmedPath = path.replace(matcher, '')
    if (!trimmedPath) {
      unsetRemoteLocation()
      setFileValidation({ validating: false, issues: {}, fileName: null })
      return false
    }

    // don't continue unless a dot is present (otherwise, no valid file extension)
    if (trimmedPath.indexOf('.') < 0 ) { return false }

    const fileType = file.file_type
    const fileExtension = `.${trimmedPath.split('.').slice(-1)[0]}`
    if (!inputAcceptExts.includes(fileExtension)) {
      const invalidExt = {
        errors: [
          [
            'error', 'filename:extension',
            `Allowed extensions are ${allowedFileExts.join(', ')}`
          ]
        ]
      }
      setFileValidation({ validating: false, issues: invalidExt, fileName: trimmedPath })
      return false
    }

    const fileOptions = fileType === 'Metadata' ? { use_metadata_convention: file?.use_metadata_convention } : {}

    setFileValidation({ validating: true, issues: {}, fileName: trimmedPath })
    try {
      const issues = await ValidateFile.validateRemoteFile(
        bucketName, trimmedPath, fileType, fileOptions
      )
      setFileValidation({ validating: false, issues, fileName: trimmedPath })

      // Prevent saving via '', if validation errors were detected
      const remoteLocation = issues.errors.length === 0 ? trimmedPath : ''
      updateFile(file._id, {remote_location: remoteLocation, hasRemoteFile: true})
    } catch (error) {
      // Catch file access error and allow user to proceed - validation will be handled server-side or in ingest
      setFileValidation({ validating: false, issues: {}, fileName: trimmedPath })
    }
  }

  const isFileChosen = !!file.upload_file_name
  const isFileOnServer = file.status !== 'new'

  let buttonText = isFileChosen ? 'Replace' : 'Choose file'
  let buttonClass = `fileinput-button btn terra-tertiary-btn`
  if (!isFileChosen && !file.uploadSelection) {
    buttonClass = 'fileinput-button btn btn-primary'
  }
  if (fileValidation.validating) {
    buttonText = <LoadingSpinner testId="file-validation-spinner"/>
  }

  let inputAcceptExts = allowedFileExts
  if (navigator.platform.includes('Mac')) {
    // A longstanding OS X file picker limitation is that compound extensions (e.g. .txt.gz)
    // will not resolve at all, so we need to add the general .gz to permit gzipped files,
    // see e.g. https://bugs.chromium.org/p/chromium/issues/detail?id=521781
    //
    // As of Chrome 111 on Mac, compound extensions with gz not only don't resolve, they
    // instantly crash the user's web browser.
    const allowedExtsWithoutCompounds =
      allowedFileExts.filter(ext => {
        return (ext.match(/\./g) || []).length === 1 // Files with 1 extension
      })

    // Allow any file that ends in .gz.  Still allows compounds extensions for upload, but
    // merely checks against a less precise list of allowed extensions.
    inputAcceptExts = [...allowedExtsWithoutCompounds, '.gz']
  }

  if (file.serverFile?.parse_status === 'failed') {
    // if the parse has failed, this file might be deleted at any minute.  Just show the name, and omit any controls
    return <div>
      <label>
        { !file.uploadSelection && <h5 data-testid="file-uploaded-name">{file.upload_file_name}</h5> }
        { file.uploadSelection && <h5 data-testid="file-selection-name">
          {file.uploadSelection.name} ({bytesToSize(file.uploadSelection.size)})
        </h5> }
      </label>
    </div>
  }

  const displayName = isAnnDataExperience && file?.data_type === 'cluster' ? file?.name : file?.upload_file_name
  return <div className="form-inline">
    <label>
      { !file.uploadSelection && <h5 data-testid="file-uploaded-name">{displayName}</h5> }
      { file.uploadSelection && <h5 data-testid="file-selection-name">
        {file.uploadSelection.name} ({bytesToSize(file.uploadSelection.size)})
      </h5> }
    </label>
    <FileDownloadControl
      file={file}
    />
    &nbsp;
    {!isFileOnServer && (showUploadButton && !file.hasRemoteFile) &&
      <button className={buttonClass} id={`fileButton-${file._id}`}
              data-testid="file-input-btn">
        {buttonText}
        <input className="file-upload-input" data-testid="file-input"
               type="file"
               id={inputId}
               onChange={handleFileSelection}
               accept={inputAcceptExts}
        />
      </button>
    }

    {!isFileOnServer && (showBucketPath || file.hasRemoteFile ) &&
      // we can't use TextFormField since we need a custom onBlur event
      // onBlur is the React equivalent of onfocusout, which will fire after the user is done updating the input
      <input className="form-control"
             type="text"
             size={60}
             id={`remote_location-input-${file._id}`}
             data-testid="remote-location-input"
             placeholder='GS URL or path to file in GCP bucket'
             onChange={ (e) => {
               const newBucketPath = e.target.value
               if (timeOutId) { clearTimeout(timeOutId) }
               const newTimeout = setTimeout(handleBucketLocationEntry, 300, newBucketPath)
               setTimeOutID(newTimeout)
             }}/>
    }
    { !isFileOnServer && (showBucketPath || file.hasRemoteFile ) && googleBucketLink }

    { !isFileOnServer && uploadToggle }

    { showBucketPath && fileValidation.validating &&
      <span className='margin-left' id='remote-location-validation'>Validating... <LoadingSpinner testId="file-validation-spinner"/></span>
    }
    <ValidationMessage
      studyAccession={study.accession}
      issues={fileValidation.issues}
      fileName={fileValidation.fileName}
    />
  </div>
}

