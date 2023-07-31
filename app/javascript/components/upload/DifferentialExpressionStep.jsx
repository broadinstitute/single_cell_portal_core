import React, { useEffect } from 'react'

import { AddFileButton } from './form-components'
import DifferentialExpressionFileForm from './DifferentialExpressionFileForm'


const DEFAULT_NEW_DE_FILE = {
  file_type: 'Differential Expression',
  differential_expression_file_info: {
    clustering_association: undefined,
    computational_method: undefined,
    annotation_name: undefined,
    annotation_scope: undefined
  }
}

export const differentialExpressionFileFilter = file => file.file_type === 'Differential Expression'

export default {
  title: 'Differential expression',
  name: 'differential expression',
  header: 'Differential expression',
  component: DifferentialFileUploadForm,
  fileFilter: differentialExpressionFileFilter
}

/** Renders a form for uploading differential expression files */
export function DifferentialFileUploadForm({
  formState,
  serverState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile,
  isAnnDataExperience,
  annotationsAvailOnStudy
}) {
  const menuOptions = serverState.menu_options

  const deFiles = formState.files.filter(differentialExpressionFileFilter)

  useEffect(() => {
    if (deFiles.length === 0) {
      addNewFile(DEFAULT_NEW_DE_FILE)
    }
  }, [deFiles.length])

  return <div>
    <div className="row">
      <div className="col-md-12">
        <p className="form-terra">
          Upload a file with differential expression for a particular clustering and annotation.  <strong>Parsed metadata
          and clustering files are required before uploading</strong>.
        </p>
      </div>
    </div>
    { deFiles.map(file => {
      return <DifferentialExpressionFileForm
        key={file.oldId ? file.oldId : file._id}
        file={file}
        allFiles={formState.files}
        updateFile={updateFile}
        saveFile={saveFile}
        deleteFile={deleteFile}
        annDataFileTypes={['AnnData']}
        bucketName={formState.study.bucket_id}
        annotationsAvailOnStudy={annotationsAvailOnStudy}
        isInitiallyExpanded={deFiles.length === 1}
        menuOptions={menuOptions}/>
    })}

    <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_DE_FILE}/>
  </div>
}


