import React from 'react'

import Select from '~/lib/InstrumentedSelect'
import { FileTypeExtensions } from './upload-utils'
import { TextFormField } from './form-components'
import ExpandableFileForm from './ExpandableFileForm'
import { validateFile } from './upload-utils'

const allowedFileExts = FileTypeExtensions.plainText

/** renders a form for editing/uploading a coordinate label file */
export default function CoordinateLabelForm({
  file,
  allFiles,
  updateFile,
  saveFile,
  deleteFile,
  associatedClusterFileOptions,
  updateCorrespondingClusters,
  bucketName,
  isInitiallyExpanded,
  isAnnDataExperience
}) {
  const associatedCluster = associatedClusterFileOptions.find(opt => opt.value === file.options.cluster_file_id)
  const validationMessages = validateFile({
    file, allFiles,
    requiredFields: [{ label: 'Corresponding cluster', propertyName: 'options.cluster_file_id' }],
    allowedFileExts
  })
  return <ExpandableFileForm {...{
    file, allFiles, updateFile, saveFile,
    allowedFileExts, deleteFile, validationMessages, bucketName, isInitiallyExpanded, isAnnDataExperience
  }}>
    <div className="form-group">
      <label className="labeled-select">Corresponding cluster / spatial data *
        <Select options={associatedClusterFileOptions}
          data-analytics-name="coordinate-labels-corresponding-cluster"
          id={`coordCluster-${file._id}`}
          value={associatedCluster}
          placeholder="Select one..."
          onChange={val => updateCorrespondingClusters(file, val)}/>
      </label>
    </div>
    <TextFormField label="Description / legend (this will be displayed below image)"
      fieldName="description" file={file} updateFile={updateFile}/>
  </ExpandableFileForm>
}
