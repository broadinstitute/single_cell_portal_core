import React from 'react'

import ExpandableFileForm from './ExpandableFileForm'
import { FileTypeExtensions, validateFile } from './upload-utils'
import { TextFormField } from './form-components'

const allowedFileExts = FileTypeExtensions.seurat

/** Renders a form for editing/uploading a seurat file */
export default function SeuratFileForm({
  file,
  allFiles,
  updateFile,
  saveFile,
  deleteFile,
  bucketName,
  isInitiallyExpanded
}) {
  const validationMessages = validateFile({ file, allFiles, allowedFileExts })
  return <ExpandableFileForm {...{
    file, allFiles, updateFile, saveFile,
    allowedFileExts, deleteFile, validationMessages, bucketName, isInitiallyExpanded
  }}>
    <TextFormField label="Description" fieldName="description" file={file} updateFile={updateFile}/>
  </ExpandableFileForm>
}
