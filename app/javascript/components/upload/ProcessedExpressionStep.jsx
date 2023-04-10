import React, { useEffect, useContext } from 'react'

import ExpressionFileForm from './ExpressionFileForm'
import { rawCountsFileFilter, getExpressionFileInfoMessage } from './RawCountsStep'
import { AddFileButton } from './form-components'

const DEFAULT_NEW_PROCESSED_FILE = {
  is_spatial: false,
  expression_file_info: {
    is_raw_counts: false,
    biosample_input_type: 'Whole cell',
    modality: 'Transcriptomic: unbiased',
    raw_counts_associations: []
  },
  file_type: 'Expression Matrix'
}

export const fileTypes = ['Expression Matrix', 'MM Coordinate Matrix']
export const processedFileFilter = file => fileTypes.includes(file.file_type) &&
  !file.expression_file_info?.is_raw_counts

export default {
  title: 'Processed matrices',
  header: 'Processed expression files',
  name: 'processed',
  component: ProcessedUploadForm,
  fileFilter: processedFileFilter
}

/** form for uploading a parent expression file and any children */
function ProcessedUploadForm({
  formState,
  serverState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile,
  setCurrentStep,
  isAnnDataExperience
}) {
  const processedParentFiles = formState.files.filter(processedFileFilter)
  const fileMenuOptions = serverState.menu_options
  const rawCountsFiles = formState.files.filter(rawCountsFileFilter).filter(
    f => f.status != 'new' && f.is_complete
  )
  const rawCountsOptions = rawCountsFiles.map(rf => ({ label: rf.name, value: rf._id }))

  const featureFlagState = serverState.feature_flags
  const rawCountsRequired = featureFlagState && featureFlagState.raw_counts_required_frontend

  const hasRawCounts = !!rawCountsFiles.filter(file => file.status === 'uploaded').length
  const isEnabled = !rawCountsRequired || hasRawCounts

  useEffect(() => {
    if (processedParentFiles.length === 0) {
      addNewFile(DEFAULT_NEW_PROCESSED_FILE)
    }
  }, [processedParentFiles.length])

  return <div>
    { !isAnnDataExperience && !isEnabled &&
      <div className="row">
        <div className="col-md-12 padded">
          <p className="margin-left">
            Uploading a raw count matrix is required before uploading a processed matrix. Raw count matrices in sparse
            (MTX) format must also include associated features/barcodes files.
          </p>
          <p className="margin-left">
            If you are unable or do not wish to upload a raw count matrix, you can request an exemption using the link
            below.
          </p>
          <div className="row">
            <div className="col-md-3 col-md-offset-2">
              <a className="action" onClick={() => setCurrentStep({ name: 'rawCounts' })}>
                <span className="fas fa-chevron-circle-left"></span> Upload Raw Count File
              </a>
            </div>
            <div className="col-md-3 col-md-offset-1">
              <a href="https://singlecell.zendesk.com/hc/en-us/requests/new?ticket_form_id=1260811597230"
                className="action"
                target="_blank"
                rel="noopener noreferrer">Request Exemption <span className="fas fa-external-link-alt"></span>
              </a>
            </div>
          </div>
        </div>
      </div>
    }
    <div className="row">
      <div className="col-md-12">
        {getExpressionFileInfoMessage(isAnnDataExperience, 'Processed')}
        {(!isAnnDataExperience && processedParentFiles.length > 1) &&
          <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_PROCESSED_FILE}/> }
        { processedParentFiles.map(file => {
          return <ExpressionFileForm
            key={file.oldId ? file.oldId : file._id}
            file={file}
            allFiles={formState.files}
            updateFile={updateFile}
            saveFile={saveFile}
            deleteFile={deleteFile}
            addNewFile={addNewFile}
            rawCountsOptions={rawCountsOptions}
            fileMenuOptions={fileMenuOptions}
            bucketName={formState.study.bucket_id}
            isInitiallyExpanded={processedParentFiles.length === 1}
            featureFlagState={featureFlagState}
            isAnnDataExperience={isAnnDataExperience}
          />
        })}
        {!isAnnDataExperience && <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_PROCESSED_FILE}/>}
        { !isEnabled && <div className="file-upload-overlay" data-testid="processed-matrix-overlay"></div> }
      </div>
    </div>
  </div>
}
