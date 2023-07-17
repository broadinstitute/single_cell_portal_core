import React, { useEffect } from 'react'

import MiscellaneousFileForm from './MiscellaneousFileForm'
import { AddFileButton } from './form-components'

const DEFAULT_NEW_OTHER_FILE = {
  file_type: 'Documentation',
  options: {}
}

const miscFileTypes = ['Other', 'Documentation']
const miscFileFilter = file => miscFileTypes.includes(file.file_type)

export default {
  title: 'Miscellaneous',
  header: 'Documentation & other files',
  name: 'misc',
  component: MiscellaneousForm,
  fileFilter: miscFileFilter
}

/** Renders a form for uploading one or more miscellaneous files */
function MiscellaneousForm({
  formState,
  addNewFile,
  updateFile,
  saveFile,
  deleteFile,
  isAnnDataExperience
}) {
  const miscFiles = formState.files.filter(miscFileFilter)

  useEffect(() => {
    if (miscFiles.length === 0) {
      addNewFile(DEFAULT_NEW_OTHER_FILE)
    }
  }, [miscFiles.length])

  return <div>
    <div className="row">
      <div className="col-md-12">
        <p className="form-terra">
          Any documentation or other support files. These files will not be used in visualizations, but will be available for users to download.
        </p>
      </div>
    </div>
    { miscFiles.map(file => {
      return <MiscellaneousFileForm
        key={file.oldId ? file.oldId : file._id}
        file={file}
        allFiles={formState.files}
        updateFile={updateFile}
        saveFile={saveFile}
        deleteFile={deleteFile}
        miscFileTypes={miscFileTypes}
        bucketName={formState.study.bucket_id}
        isInitiallyExpanded={miscFiles.length === 1}
        isAnnDataExperience={isAnnDataExperience}
      />
    })}
    <AddFileButton addNewFile={addNewFile} newFileTemplate={DEFAULT_NEW_OTHER_FILE}/>
  </div>
}
