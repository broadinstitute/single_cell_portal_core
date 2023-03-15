import React, { useEffect } from 'react'

import ExpressionFileForm from './ExpressionFileForm'
import { getExpressionFileInfoMessage } from './RawCountsStep'

const DEFAULT_NEW_PROCESSED_FILE = {
  is_spatial: false,
  expression_file_info: {
    is_raw_counts: false,
    biosample_input_type: 'Whole cell',
    modality: 'Transcriptomic: unbiased'
  },
  file_type: 'Expression Matrix'
}

export const fileTypes = ['Expression Matrix', 'MM Coordinate Matrix']
export const processedFileFilter = file => fileTypes.includes(file.file_type) &&
  !file.expression_file_info?.is_raw_counts

export default {
  title: 'Expression matrices',
  header: 'Expression matrices',
  name: 'combined expression matrices',
  component: ExpressionUploadForm,
  fileFilter: processedFileFilter
}

/** form for uploading a parent expression file and any children */
function ExpressionUploadForm({
  formState,
  serverState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile,
  isAnnDataExperience
}) {
  const processedParentFiles = formState.files.filter(processedFileFilter)
  const fileMenuOptions = serverState.menu_options

  const featureFlagState = serverState.feature_flags

  useEffect(() => {
    if (processedParentFiles.length === 0) {
      addNewFile(DEFAULT_NEW_PROCESSED_FILE)
    }
  }, [processedParentFiles.length])

  return <div>
    <div className="row">
      <div className="col-md-12">
        {getExpressionFileInfoMessage(isAnnDataExperience, 'Processed')}
        { processedParentFiles.map(file => {
          return <ExpressionFileForm
            key={file.oldId ? file.oldId : file._id}
            file={file}
            allFiles={formState.files}
            updateFile={updateFile}
            saveFile={saveFile}
            deleteFile={deleteFile}
            addNewFile={addNewFile}
            fileMenuOptions={fileMenuOptions}
            bucketName={formState.study.bucket_id}
            isInitiallyExpanded={true}
            isRawCountsFile={true}
            featureFlagState={featureFlagState}
            isAnnDataExperience={isAnnDataExperience}/>
        })}
      </div>
    </div>
  </div>
}
