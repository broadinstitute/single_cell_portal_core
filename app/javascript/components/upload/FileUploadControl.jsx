import React, { useState, useContext } from 'react'

import { bytesToSize } from '~/lib/stats'
import FileDownloadControl from '~/components/download/FileDownloadControl'
import LoadingSpinner from '~/lib/LoadingSpinner'
import { StudyContext } from '~/components/upload/upload-utils'
import ValidateFile from '~/lib/validation/validate-file'
import ValidationMessage from '~/components/validation/ValidationMessage'

// File types which let the user set a custom name for the file in the UX
const FILE_TYPES_ALLOWING_SET_NAME = ['Cluster', 'Gene List', 'Image']


/** renders a file upload control for the given file object */
export default function FileUploadControl({
  file, allFiles, updateFile,
  allowedFileExts=['*'],
  validationIssues={},
  bucketName
}) {
  const [fileValidation, setFileValidation] = useState({
    validating: false, issues: {}, fileName: null
  })
  const inputId = `file-input-${file._id}`

  const study = useContext(StudyContext)

  /** handle user interaction with the file input */
  async function handleFileSelection(e) {
    const selectedFile = e.target.files[0]

    let newName = selectedFile.name

    // for cluster and other named files, don't change an existing customized name
    if (FILE_TYPES_ALLOWING_SET_NAME.includes(file.file_type) && file.name && file.name !== file.upload_file_name) {
      newName = file.name
    }
    setFileValidation({ validating: true, issues: {}, fileName: selectedFile.name })
    const issues = await ValidateFile.validateLocalFile(selectedFile, file, allFiles, allowedFileExts)
    setFileValidation({ validating: false, issues, fileName: selectedFile.name })
    if (issues.errors.length === 0) {
      updateFile(file._id, {
        uploadSelection: selectedFile,
        upload_file_name: selectedFile.name,
        name: newName
      })
    }
  }
  const isFileChosen = !!file.upload_file_name
  const isFileOnServer = file.status !== 'new'

  let buttonText = isFileChosen ? 'Replace' : 'Choose file'
  let buttonClass = 'fileinput-button btn terra-tertiary-btn'
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

  return <div>
    <label>
      { !file.uploadSelection && <h5 data-testid="file-uploaded-name">{file.upload_file_name}</h5> }
      { file.uploadSelection && <h5 data-testid="file-selection-name">
        {file.uploadSelection.name} ({bytesToSize(file.uploadSelection.size)})
      </h5> }
    </label>
    <FileDownloadControl
      file={file}
    />
    &nbsp;
    { !isFileOnServer &&
      <button className={buttonClass} id={`fileButton-${file._id}`} data-testid="file-input-btn">
        { buttonText }
        <input className="file-upload-input" data-testid="file-input"
          type="file"
          id={inputId}
          onChange={handleFileSelection}
          accept={inputAcceptExts}
        />
      </button>
    }

    <ValidationMessage
      studyAccession={study.accession}
      issues={fileValidation.issues}
      fileName={fileValidation.fileName}
    />
  </div>
}

