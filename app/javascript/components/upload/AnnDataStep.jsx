import React, { useEffect } from 'react'

import AnnDataFileForm from './AnnDataFileForm'
import { AddFileButton } from './form-components'

const DEFAULT_NEW_ANNDATA_FILE = {
  file_type: 'AnnData',
  options: {}
}

export const AnnDataFileFilter = file => ['AnnData'].includes(file.file_type)

export default {
  title: 'AnnData (.h5ad)',
  header: 'AnnData files',
  name: 'AnnData',
  component: AnnDataForm,
  fileFilter: AnnDataFileFilter
}

/** Renders a form for uploading one or more AnnData files */
function AnnDataForm({
  formState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile
}) {
  const AnnDataFiles = formState.files.filter(AnnDataFileFilter)
  useEffect(() => {
    if (AnnDataFiles.length === 0) {
      addNewFile(DEFAULT_NEW_ANNDATA_FILE)
    }
  }, [AnnDataFiles.length])

  return <div>
    <div className="row">
      <div className="col-md-12">
        <p className="form-terra">
          AnnData files are typically formatted with the file extension .h5ad.&nbsp;
          <a href="https://anndata.readthedocs.io" target="_blank" rel="noreferrer">
            See reference documentation
          </a>.
          <br></br>
          These files will not be used to power visualizations, but will be available for users to download.
        </p>
      </div>
    </div>
    { AnnDataFiles.map(file => {
      return <AnnDataFileForm
        key={file.oldId ? file.oldId : file._id}
        file={file}
        allFiles={formState.files}
        updateFile={updateFile}
        saveFile={saveFile}
        deleteFile={deleteFile}
        annDataFileTypes={['AnnData']}
        bucketName={formState.study.bucket_id}
        isInitiallyExpanded={AnnDataFiles.length === 1}/>
    })}
    <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_ANNDATA_FILE}/>
  </div>
}
