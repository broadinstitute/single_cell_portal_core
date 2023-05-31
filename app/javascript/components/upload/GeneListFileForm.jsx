import React from 'react'

import { FileTypeExtensions } from './upload-utils'
import { TextFormField } from './form-components'
import { validateFile } from './upload-utils'
import ExpandableFileForm from './ExpandableFileForm'


/** renders a form for editing/uploading a miscellaneous file */
export default function GeneListFileForm({
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
  const allowedFileExts = FileTypeExtensions.plainText

  const validationMessages = validateFile({ file, allFiles, allowedFileExts })

  const heatmapInfo = file.heatmap_file_info ?? {}
  const showManualHeatmapControls = heatmapInfo.custom_scaling

  return <ExpandableFileForm {...{
    file, allFiles, updateFile, saveFile,
    allowedFileExts, deleteFile, validationMessages, bucketName, isInitiallyExpanded, isAnnDataExperience
  }}>
    <TextFormField label="Name" fieldName="name" file={file} updateFile={updateFile}/>
    <TextFormField label="Description (shown above heatmap)" fieldName="description" file={file} updateFile={updateFile}/>
    <TextFormField label="Computed value name (legend label)" fieldName="heatmap_file_info.legend_label" file={file} updateFile={updateFile}/>
    <div className="form-group">
      <label>Color scale</label><br/>
      <label className="sublabel">
        <input type="radio"
          name={`heatmapCustomFalse-${file._id}`}
          value={false}
          checked={!heatmapInfo.custom_scaling}
          onChange={e => updateFile(file._id, { heatmap_file_info: { custom_scaling: false } })} /> Row-relative (e.g. gene expression heatmaps)
      </label><br/>
      <label className="sublabel">
        <input type="radio"
          name={`heatmapCustomTrue-${file._id}`}
          value={true}
          checked={heatmapInfo.custom_scaling}
          onChange={e => updateFile(file._id, { heatmap_file_info: { custom_scaling: true } })} /> Specify color range
      </label>
      { showManualHeatmapControls &&
        <div className="row margin-left">
          <div className="col-md-2">
            <TextFormField label="min" fieldName="heatmap_file_info.color_min" file={file} updateFile={updateFile}/>
          </div>
          <div className="col-md-2">
            <TextFormField label="max" fieldName="heatmap_file_info.color_max" file={file} updateFile={updateFile}/>
          </div>
        </div>
      }
    </div>
  </ExpandableFileForm>
}
