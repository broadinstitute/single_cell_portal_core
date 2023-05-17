import React from 'react'

import Select from '~/lib/InstrumentedSelect'
import ExpandableFileForm from './ExpandableFileForm'
import { FileTypeExtensions, validateFile } from './upload-utils'
import { TextFormField } from './form-components'

const allowedFileExts = FileTypeExtensions.misc

/** renders a form for editing/uploading a miscellaneous file */
export default function MiscellaneousFileForm({
  file,
  allFiles,
  updateFile,
  saveFile,
  deleteFile,
  miscFileTypes,
  bucketName,
  isInitiallyExpanded,
  isAnnDataExperience
}) {
  const validationMessages = validateFile({ file, allFiles, allowedFileExts })
  return <ExpandableFileForm {...{
    file, allFiles, updateFile, saveFile,
    allowedFileExts, deleteFile, validationMessages, bucketName, isInitiallyExpanded, isAnnDataExperience
  }}>
    <div className="form-group">
      <label className="labeled-select">File type:
        <Select options={miscFileTypes.map(ft => ({ label: ft, value: ft }))}
          data-analytics-name="misc-file-type"
          value={{ label: file.file_type, value: file.file_type }}
          onChange={val => updateFile(file._id, { file_type: val.value })}/>
      </label>
    </div>

    <TextFormField label="Description" fieldName="description" file={file} updateFile={updateFile}/>
  </ExpandableFileForm>
}
