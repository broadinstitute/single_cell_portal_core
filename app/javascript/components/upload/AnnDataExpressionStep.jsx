import React, { useEffect } from 'react'

import ExpressionFileForm from './ExpressionFileForm'
import { getExpressionFileInfoMessage } from './RawCountsStep'
import { matchingFormFiles } from '~/components/upload/upload-utils'

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
export const annDataExpFilter = file => fileTypes.includes(file.file_type)

export default {
  title: 'Expression matrices',
  header: 'Expression matrices',
  name: 'combined expression matrices',
  component: ExpressionUploadForm,
  fileFilter: annDataExpFilter
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
  const fragmentType = isAnnDataExperience ? 'expression' : null
  const annDataExpFiles = matchingFormFiles(
    formState.files, annDataExpFilter, isAnnDataExperience, fragmentType
  )
  const fileMenuOptions = serverState.menu_options

  const featureFlagState = serverState.feature_flags

  useEffect(() => {
    if (annDataExpFiles.length === 0) {
      addNewFile(DEFAULT_NEW_PROCESSED_FILE)
    }
  }, [annDataExpFiles.length])

  return <div>
    <div className="row">
      <div className="col-md-12">
        {getExpressionFileInfoMessage(isAnnDataExperience, 'Processed')}
        { annDataExpFiles.map(file => {
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
