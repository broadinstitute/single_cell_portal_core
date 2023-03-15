import React, { useEffect } from 'react'

import AnnDataFileForm from './AnnDataFileForm'
import { AnnDataFileFilter } from './AnnDataStep'

const DEFAULT_NEW_ANNDATA_FILE = {
  file_type: 'AnnData',
  options: {}
}

export default {
  title: 'AnnData',
  header: 'AnnData file',
  name: 'AnnData file',
  component: AnnDataUploadStep,
  fileFilter: AnnDataFileFilter
}

/** Renders a form for uploading one or more AnnData files */
function AnnDataUploadStep({
  formState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile,
  isAnnDataExperience,
  deleteFileFromForm
}) {
  const AnnDataFile = formState.files.filter(AnnDataFileFilter)
  useEffect(() => {
    if (AnnDataFile.length === 0) {
      addNewFile(DEFAULT_NEW_ANNDATA_FILE)
    }
  }, [[AnnDataFile?._id]])

  return <div>
    <div className="row">
      <div className="col-md-12">
        <p className="form-terra">
          AnnData files, typically formatted with the file extension .h5ad.&nbsp;
          <a href="https://anndata.readthedocs.io" target="_blank" rel="noreferrer">
            See reference documentation
          </a>.
        </p>
      </div>
    </div>
    { AnnDataFile.map(file => {
      return <AnnDataFileForm
        key={file.oldId ? file.oldId : file._id}
        file={file}
        allFiles={formState.files}
        updateFile={updateFile}
        saveFile={saveFile}
        deleteFile={deleteFile}
        annDataFileTypes={['AnnData']}
        bucketName={formState.study.bucket_id}
        isInitiallyExpanded={true}
        isAnnDataExperience={isAnnDataExperience}/>
    })}
  </div>
}
